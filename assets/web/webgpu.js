import { createJoltEnv } from "./jolt_bridge.js";

const debugParams = new URLSearchParams(window.location.search);
const phasorDebug = {
  lifecycleLogs: debugParams.has("phasor_debug_lifecycle"),
  hotPathWarnings: debugParams.has("phasor_debug_hotpath"),
  frameWatchdog: debugParams.has("phasor_debug_watchdog"),
};
if (phasorDebug.lifecycleLogs) {
  console.log("[phasor] webgpu.js loaded");
}

const wasmUrl = new URL("app.wasm", import.meta.url);
const triangleShaderUrl = new URL("shaders/triangle.wgsl", import.meta.url);
const quadShaderUrl = new URL("shaders/quad.wgsl", import.meta.url);
const meshTexturedShaderUrl = new URL("shaders/mesh_textured.wgsl", import.meta.url);
const sceneUniformsSize = 2352;
const shadowUniformsSize = 96;
const instanceStrideBytes = 160;
const instanceFloatCount = instanceStrideBytes / 4;

const ctxs = new Map();
let nextCtxId = 1;
let wasm = null;
let memory = null;
let device = null;
let wasmApp = 0;
let shaderSources = null;
let audioCtx = null;
let deviceLost = false;
let simulationPaused = false;
let pauseOnGpuError = false;
let useVsync = true;
let wantsMouseCapture = false;
let resumeFrameLoop = null;
let recoveringDevice = false;
const webgpuErrors = {
  validation: 0,
  outOfMemory: 0,
  internal: 0,
};
const webgpuCreates = {
  buffers: 0,
  textures: 0,
  textureViews: 0,
  samplers: 0,
  bindGroups: 0,
  pipelines: 0,
  commandEncoders: 0,
  renderPasses: 0,
};
const webgpuDestroys = {
  buffers: 0,
  textures: 0,
  samplers: 0,
  bindGroups: 0,
  pipelines: 0,
};
let webgpuFramesBegun = 0;
let webgpuFramesEnded = 0;
let instanceScratchBuffer = null;
let instanceScratchBytes = 0;
let gpuFramesInFlight = 0;
const maxFramesInFlight = 2;
const enableRecovery = false;
let frameIndex = 0;
let lastDepthRebuildFrame = -1;
let resizeCalls = 0;
let depthRebuilds = 0;
let lastQueueWaitMs = 0;
let maxQueueWaitMs = 0;
let queueWaitPending = false;
let lastFrameScheduledAtMs = 0;
let lastFrameStartedAtMs = 0;
let lastFrameFinishedAtMs = 0;
let lastWatchdogKickAtMs = 0;
let frameTimeoutId = null;
let frameWatchdogIntervalId = null;
let lastReportedWasmError = "ok";
const lastFrameCounts = {
  buffers: 0,
  textures: 0,
  textureViews: 0,
  samplers: 0,
  bindGroups: 0,
  pipelines: 0,
  commandEncoders: 0,
  renderPasses: 0,
};
const soundBuffers = new Map();
const activeSounds = new Map();
let nextSoundId = 1;
let nextSoundHandle = 1;
const joltEnv = createJoltEnv(() => getMemoryView());

const textDecoder = new TextDecoder("utf-8");

const keyCodeMap = {
  Space: 32,
  ArrowLeft: 263,
  ArrowRight: 262,
  ArrowUp: 265,
  ArrowDown: 264,
  Escape: 256,
  Enter: 257,
};

function mapKeyboardEvent(event) {
  const code = event.code;
  if (!code) return null;
  if (code.startsWith("Key") && code.length === 4) {
    const ch = code.charCodeAt(3);
    if (ch >= 65 && ch <= 90) return ch;
  }
  if (Object.prototype.hasOwnProperty.call(keyCodeMap, code)) {
    return keyCodeMap[code];
  }
  return null;
}

function getMemoryView() {
  return new DataView(memory.buffer);
}

function float32ToFloat16(value) {
  if (!Number.isFinite(value)) {
    return value > 0 ? 0x7c00 : 0xfc00;
  }
  if (value === 0) {
    return (1 / value) === -Infinity ? 0x8000 : 0;
  }

  const floatView = new Float32Array(1);
  const intView = new Uint32Array(floatView.buffer);
  floatView[0] = value;
  const bits = intView[0];
  const sign = (bits >>> 16) & 0x8000;
  let exponent = ((bits >>> 23) & 0xff) - 127 + 15;
  let mantissa = bits & 0x7fffff;

  if (exponent <= 0) {
    if (exponent < -10) return sign;
    mantissa = (mantissa | 0x800000) >>> (1 - exponent);
    return sign | ((mantissa + 0x1000) >>> 13);
  }
  if (exponent >= 0x1f) {
    return sign | 0x7c00;
  }
  return sign | (exponent << 10) | ((mantissa + 0x1000) >>> 13);
}

function ensureAudioContext() {
  if (!audioCtx) {
    const AudioContext = window.AudioContext || window.webkitAudioContext;
    audioCtx = AudioContext ? new AudioContext() : null;
  }
  if (audioCtx && audioCtx.state === "suspended") {
    audioCtx.resume().catch(() => {});
  }
  return audioCtx;
}


function readString(ptr, len) {
  return textDecoder.decode(new Uint8Array(memory.buffer, ptr, len));
}

function setPageTitle(title) {
  if (!title) return;
  document.title = title;
  const header = document.querySelector("#app-title");
  if (header) header.textContent = title;
}

function captureLastWasmError() {
  if (!wasm || !wasm.exports || !wasm.exports.wasmLastErrorPtr || !wasm.exports.wasmLastErrorLen) {
    return "unavailable";
  }
  const ptr = wasm.exports.wasmLastErrorPtr();
  const len = wasm.exports.wasmLastErrorLen();
  if (!ptr || !len) return "ok";
  return readString(ptr, len);
}

function reportWasmError(reason) {
  if (!reason || reason === "ok" || reason === lastReportedWasmError) return;
  lastReportedWasmError = reason;
  console.error("[phasor] wasm error:", reason);
  const hint = document.querySelector(".hint");
  if (hint) hint.textContent = `WebGPU: wasm error (${reason})`;
}

function resizeCanvas(canvas) {
  const scale = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const measuredLogicalWidth = Math.floor(rect.width);
  const measuredLogicalHeight = Math.floor(rect.height);
  const fallbackLogicalWidth = Math.max(
    1,
    Math.floor(
      canvas.clientWidth ||
      (canvas.width > 1 ? canvas.width / scale : window.innerWidth || 1),
    ),
  );
  const fallbackLogicalHeight = Math.max(
    1,
    Math.floor(
      canvas.clientHeight ||
      (canvas.height > 1 ? canvas.height / scale : window.innerHeight || 1),
    ),
  );
  const logicalWidth = measuredLogicalWidth > 1 ? measuredLogicalWidth : fallbackLogicalWidth;
  const logicalHeight = measuredLogicalHeight > 1 ? measuredLogicalHeight : fallbackLogicalHeight;
  const measuredFramebufferWidth = Math.floor(rect.width * scale);
  const measuredFramebufferHeight = Math.floor(rect.height * scale);
  const fallbackFramebufferWidth = Math.max(1, Math.floor(fallbackLogicalWidth * scale));
  const fallbackFramebufferHeight = Math.max(1, Math.floor(fallbackLogicalHeight * scale));
  const framebufferWidth = measuredFramebufferWidth > 1 ? measuredFramebufferWidth : fallbackFramebufferWidth;
  const framebufferHeight = measuredFramebufferHeight > 1 ? measuredFramebufferHeight : fallbackFramebufferHeight;
  if (canvas.width !== framebufferWidth || canvas.height !== framebufferHeight) {
    canvas.width = framebufferWidth;
    canvas.height = framebufferHeight;
  }
  return {
    logicalWidth,
    logicalHeight,
    framebufferWidth,
    framebufferHeight,
  };
}

function createBufferWithData(device, data, usage) {
  const buffer = device.createBuffer({
    size: data.byteLength,
    usage: usage | GPUBufferUsage.COPY_DST,
  });
  webgpuCreates.buffers += 1;
  const bytes = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  device.queue.writeBuffer(buffer, 0, bytes);
  return buffer;
}

function createDepthTexture(ctx, width, height) {
  if (ctx.depthTexture) {
    ctx.depthTexture.destroy();
    webgpuDestroys.textures += 1;
  }
  depthRebuilds += 1;
  lastDepthRebuildFrame = frameIndex;
  ctx.depthTexture = ctx.device.createTexture({
    size: { width, height },
    format: "depth24plus",
    usage: GPUTextureUsage.RENDER_ATTACHMENT,
  });
  webgpuCreates.textures += 1;
  ctx.depthView = ctx.depthTexture.createView();
  webgpuCreates.textureViews += 1;
}

function createShadowMapSlot(ctx, width, height) {
  const texture = ctx.device.createTexture({
    size: { width, height },
    format: "depth32float",
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
  });
  webgpuCreates.textures += 1;
  const view = texture.createView();
  webgpuCreates.textureViews += 1;
  return { texture, view, width, height };
}

function destroyShadowMapSlot(slot) {
  if (!slot) return;
  if (slot.texture) {
    slot.texture.destroy();
    webgpuDestroys.textures += 1;
  }
}

async function loadShaders() {
  if (shaderSources) return shaderSources;
  const [triangleShader, quadShader, meshTexturedShader] = await Promise.all([
    fetch(triangleShaderUrl).then((resp) => resp.text()),
    fetch(quadShaderUrl).then((resp) => resp.text()),
    fetch(meshTexturedShaderUrl).then((resp) => resp.text()),
  ]);
  shaderSources = {
    triangleShader,
    quadShader,
    meshTexturedShader,
  };
  return shaderSources;
}

function createPipelines(ctx) {
  if (!shaderSources) {
    throw new Error("Shaders not loaded");
  }
  const triangleShader = shaderSources.triangleShader;
  const quadShader = shaderSources.quadShader;
  const meshTexturedShader = shaderSources.meshTexturedShader;
  const depthState = {
    format: "depth24plus",
    depthWriteEnabled: true,
    depthCompare: "less-equal",
  };
  const depthStateBlend = {
    format: "depth24plus",
    depthWriteEnabled: false,
    depthCompare: "less-equal",
  };

  const triangleModule = ctx.device.createShaderModule({ code: triangleShader });
  const quadModule = ctx.device.createShaderModule({ code: quadShader });
  const meshTexturedModule = ctx.device.createShaderModule({ code: meshTexturedShader });
  webgpuCreates.pipelines += 4;

  ctx.trianglePipeline = ctx.device.createRenderPipeline({
    layout: "auto",
    vertex: {
      module: triangleModule,
      entryPoint: "vs_main",
      buffers: [{
        arrayStride: 20,
        attributes: [
          { shaderLocation: 0, offset: 0, format: "float32x2" },
          { shaderLocation: 1, offset: 8, format: "float32x3" },
        ],
      }],
    },
    fragment: {
      module: triangleModule,
      entryPoint: "fs_main",
      targets: [{ format: ctx.format }],
    },
    depthStencil: depthState,
    primitive: { topology: "triangle-list" },
  });

  ctx.quadBindGroupLayout = ctx.device.createBindGroupLayout({
    entries: [
      { binding: 0, visibility: GPUShaderStage.FRAGMENT, sampler: { type: "filtering" } },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
    ],
  });
  const quadPipelineLayout = ctx.device.createPipelineLayout({
    bindGroupLayouts: [ctx.quadBindGroupLayout],
  });
  webgpuCreates.pipelines += 2;
  ctx.quadPipelineOpaque = ctx.device.createRenderPipeline({
    layout: quadPipelineLayout,
    vertex: {
      module: quadModule,
      entryPoint: "vs_main",
      buffers: [
        {
          arrayStride: 16,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x2" },
            { shaderLocation: 1, offset: 8, format: "float32x2" },
          ],
        },
        {
          arrayStride: instanceStrideBytes,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
            { shaderLocation: 6, offset: 128, format: "float32x4" },
          ],
        },
      ],
    },
    fragment: {
      module: quadModule,
      entryPoint: "fs_main",
      targets: [{
        format: ctx.format,
      }],
    },
    depthStencil: depthState,
    primitive: { topology: "triangle-list" },
  });

  ctx.quadPipelineBlend = ctx.device.createRenderPipeline({
    layout: quadPipelineLayout,
    vertex: {
      module: quadModule,
      entryPoint: "vs_main",
      buffers: [
        {
          arrayStride: 16,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x2" },
            { shaderLocation: 1, offset: 8, format: "float32x2" },
          ],
        },
        {
          arrayStride: instanceStrideBytes,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
            { shaderLocation: 6, offset: 128, format: "float32x4" },
          ],
        },
      ],
    },
    fragment: {
      module: quadModule,
      entryPoint: "fs_main",
      targets: [{
        format: ctx.format,
        blend: {
          color: { operation: "add", srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha" },
          alpha: { operation: "add", srcFactor: "one", dstFactor: "one-minus-src-alpha" },
        },
      }],
    },
    depthStencil: depthStateBlend,
    primitive: { topology: "triangle-list" },
  });

  ctx.meshTexturedPipelineOpaque = ctx.device.createRenderPipeline({
    layout: quadPipelineLayout,
    vertex: {
      module: meshTexturedModule,
      entryPoint: "vs_main",
      buffers: [
        {
          arrayStride: 20,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x3" },
            { shaderLocation: 1, offset: 12, format: "float32x2" },
          ],
        },
        {
          arrayStride: instanceStrideBytes,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
            { shaderLocation: 6, offset: 128, format: "float32x4" },
          ],
        },
      ],
    },
    fragment: {
      module: meshTexturedModule,
      entryPoint: "fs_main",
      targets: [{ format: ctx.format }],
    },
    depthStencil: depthState,
    primitive: { topology: "triangle-list" },
  });

  ctx.meshTexturedPipelineBlend = ctx.device.createRenderPipeline({
    layout: quadPipelineLayout,
    vertex: {
      module: meshTexturedModule,
      entryPoint: "vs_main",
      buffers: [
        {
          arrayStride: 20,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x3" },
            { shaderLocation: 1, offset: 12, format: "float32x2" },
          ],
        },
        {
          arrayStride: instanceStrideBytes,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
            { shaderLocation: 6, offset: 128, format: "float32x4" },
          ],
        },
      ],
    },
    fragment: {
      module: meshTexturedModule,
      entryPoint: "fs_main",
      targets: [{
        format: ctx.format,
        blend: {
          color: { operation: "add", srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha" },
          alpha: { operation: "add", srcFactor: "one", dstFactor: "one-minus-src-alpha" },
        },
      }],
    },
    depthStencil: depthStateBlend,
    primitive: { topology: "triangle-list" },
  });

  ctx.postProcessBindGroupLayout = ctx.device.createBindGroupLayout({
    entries: [
      { binding: 0, visibility: GPUShaderStage.FRAGMENT, sampler: { type: "filtering" } },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
      {
        binding: 2,
        visibility: GPUShaderStage.FRAGMENT,
        buffer: { type: "uniform", minBindingSize: 80 },
      },
    ],
  });
  ctx.postProcessPipelineLayout = ctx.device.createPipelineLayout({
    bindGroupLayouts: [ctx.postProcessBindGroupLayout],
  });
  ctx.postProcessSampler = ctx.device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
    mipmapFilter: "linear",
    addressModeU: "clamp-to-edge",
    addressModeV: "clamp-to-edge",
    addressModeW: "clamp-to-edge",
  });
  ctx.postProcessUniformBuffer = ctx.device.createBuffer({
    size: 80,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  ctx.sceneBindGroupLayout = ctx.device.createBindGroupLayout({
    entries: [
      { binding: 0, visibility: GPUShaderStage.FRAGMENT, sampler: { type: "filtering" } },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
      {
        binding: 2,
        visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
        buffer: { type: "uniform", minBindingSize: sceneUniformsSize },
      },
      { binding: 3, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
      { binding: 4, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
      { binding: 5, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
    ],
  });
  ctx.scenePipelineLayout = ctx.device.createPipelineLayout({
    bindGroupLayouts: [ctx.sceneBindGroupLayout],
  });
  ctx.sceneMaterialBindGroupLayout = ctx.device.createBindGroupLayout({
    entries: [
      { binding: 0, visibility: GPUShaderStage.FRAGMENT, sampler: { type: "filtering" } },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
      { binding: 2, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
      { binding: 3, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
      { binding: 4, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
    ],
  });
  ctx.sceneEnvironmentBindGroupLayout = ctx.device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
        buffer: { type: "uniform", minBindingSize: sceneUniformsSize },
      },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, sampler: { type: "filtering" } },
      { binding: 2, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "float" } },
    ],
  });
  ctx.shadowBindGroupLayout = ctx.device.createBindGroupLayout({
    entries: [
      {
        binding: 0,
        visibility: GPUShaderStage.VERTEX | GPUShaderStage.FRAGMENT,
        buffer: { type: "uniform", minBindingSize: shadowUniformsSize },
      },
      { binding: 1, visibility: GPUShaderStage.FRAGMENT, sampler: { type: "comparison" } },
      { binding: 2, visibility: GPUShaderStage.FRAGMENT, texture: { sampleType: "depth" } },
    ],
  });
  ctx.sceneShadowPipelineLayout = ctx.device.createPipelineLayout({
    bindGroupLayouts: [ctx.sceneBindGroupLayout, ctx.shadowBindGroupLayout],
  });
  ctx.sceneEnvironmentPipelineLayout = ctx.device.createPipelineLayout({
    bindGroupLayouts: [ctx.sceneMaterialBindGroupLayout, ctx.sceneEnvironmentBindGroupLayout, ctx.shadowBindGroupLayout],
  });
  ctx.sceneUniformBuffer = ctx.device.createBuffer({
    size: sceneUniformsSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  ctx.shadowUniformBuffer = ctx.device.createBuffer({
    size: shadowUniformsSize,
    usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
  });
  ctx.shadowSampler = ctx.device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
    mipmapFilter: "nearest",
    addressModeU: "clamp-to-edge",
    addressModeV: "clamp-to-edge",
    addressModeW: "clamp-to-edge",
    compare: "less-equal",
  });
  ctx.sceneEnvironmentSampler = ctx.device.createSampler({
    magFilter: "linear",
    minFilter: "linear",
    mipmapFilter: "linear",
    addressModeU: "clamp-to-edge",
    addressModeV: "clamp-to-edge",
    addressModeW: "clamp-to-edge",
  });
  webgpuCreates.samplers += 3;
  webgpuCreates.buffers += 3;

  const defaultSceneEnvironmentTexture = ctx.device.createTexture({
    size: { width: 1, height: 1 },
    format: "rgba16float",
    usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
  });
  webgpuCreates.textures += 1;
  const defaultSceneEnvironmentView = defaultSceneEnvironmentTexture.createView();
  webgpuCreates.textureViews += 1;
  ctx.queue.writeTexture(
    { texture: defaultSceneEnvironmentTexture },
    new Uint16Array([0, 0, 0, float32ToFloat16(1.0)]),
    { bytesPerRow: 8 },
    { width: 1, height: 1 },
  );
  ctx.defaultSceneEnvironment = {
    texture: defaultSceneEnvironmentTexture,
    view: defaultSceneEnvironmentView,
  };
  ctx.sceneEnvironmentBindGroup = ctx.device.createBindGroup({
    layout: ctx.sceneEnvironmentBindGroupLayout,
    entries: [
      {
        binding: 0,
        resource: {
          buffer: ctx.sceneUniformBuffer,
          offset: 0,
          size: sceneUniformsSize,
        },
      },
      { binding: 1, resource: ctx.sceneEnvironmentSampler },
      { binding: 2, resource: defaultSceneEnvironmentView },
    ],
  });
  webgpuCreates.bindGroups += 1;
}

function createColorPipelinesFromWgsl(ctx, wgslSource) {
  const module = ctx.device.createShaderModule({ code: wgslSource });
  const depthState = {
    format: "depth24plus",
    depthWriteEnabled: true,
    depthCompare: "less-equal",
  };
  const depthStateBlend = {
    format: "depth24plus",
    depthWriteEnabled: false,
    depthCompare: "less-equal",
  };
  const vertexBuffers = [
    {
      arrayStride: 28,
      attributes: [
        { shaderLocation: 0, offset: 0, format: "float32x3" },
        { shaderLocation: 1, offset: 12, format: "float32x4" },
      ],
    },
    {
      arrayStride: instanceStrideBytes,
      stepMode: "instance",
      attributes: [
        { shaderLocation: 2, offset: 0, format: "float32x4" },
        { shaderLocation: 3, offset: 16, format: "float32x4" },
        { shaderLocation: 4, offset: 32, format: "float32x4" },
        { shaderLocation: 5, offset: 48, format: "float32x4" },
        { shaderLocation: 6, offset: 128, format: "float32x4" },
      ],
    },
  ];

  const opaque = ctx.device.createRenderPipeline({
    layout: "auto",
    vertex: {
      module,
      entryPoint: "vs_main",
      buffers: vertexBuffers,
    },
    fragment: {
      module,
      entryPoint: "fs_main",
      targets: [{ format: ctx.format }],
    },
    depthStencil: depthState,
    primitive: { topology: "triangle-list" },
  });

  const blend = ctx.device.createRenderPipeline({
    layout: "auto",
    vertex: {
      module,
      entryPoint: "vs_main",
      buffers: vertexBuffers,
    },
    fragment: {
      module,
      entryPoint: "fs_main",
      targets: [{
        format: ctx.format,
        blend: {
          color: { operation: "add", srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha" },
          alpha: { operation: "add", srcFactor: "one", dstFactor: "one-minus-src-alpha" },
        },
      }],
    },
    depthStencil: depthStateBlend,
    primitive: { topology: "triangle-list" },
  });
  webgpuCreates.pipelines += 2;
  return { opaque, blend };
}

function createMaterialPipelinesFromWgsl(ctx, wgslSource, vertexLayout, bindingMode = 1) {
  const module = ctx.device.createShaderModule({ code: wgslSource });
  const depthState = {
    format: "depth24plus",
    depthWriteEnabled: true,
    depthCompare: "less-equal",
  };
  const depthStateBlend = {
    format: "depth24plus",
    depthWriteEnabled: false,
    depthCompare: "less-equal",
  };
  const materialPipelineLayout = bindingMode === 2
    ? ctx.sceneShadowPipelineLayout
    : bindingMode === 3
      ? ctx.sceneEnvironmentPipelineLayout
      : ctx.device.createPipelineLayout({
          bindGroupLayouts: [ctx.quadBindGroupLayout],
        });

  const vertexBuffers = vertexLayout === 0
    ? [
        {
          arrayStride: 16,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x2" },
            { shaderLocation: 1, offset: 8, format: "float32x2" },
          ],
        },
        {
          arrayStride: instanceStrideBytes,
          stepMode: "instance",
          attributes: bindingMode === 2 || bindingMode === 3
            ? [
                { shaderLocation: 2, offset: 0, format: "float32x4" },
                { shaderLocation: 3, offset: 16, format: "float32x4" },
                { shaderLocation: 4, offset: 32, format: "float32x4" },
                { shaderLocation: 5, offset: 48, format: "float32x4" },
                { shaderLocation: 6, offset: 64, format: "float32x4" },
                { shaderLocation: 7, offset: 80, format: "float32x4" },
                { shaderLocation: 8, offset: 96, format: "float32x4" },
                { shaderLocation: 9, offset: 112, format: "float32x4" },
                { shaderLocation: 10, offset: 128, format: "float32x4" },
                { shaderLocation: 11, offset: 144, format: "float32x4" },
              ]
            : [
                { shaderLocation: 2, offset: 0, format: "float32x4" },
                { shaderLocation: 3, offset: 16, format: "float32x4" },
                { shaderLocation: 4, offset: 32, format: "float32x4" },
                { shaderLocation: 5, offset: 48, format: "float32x4" },
                { shaderLocation: 6, offset: 128, format: "float32x4" },
              ],
        },
      ]
    : vertexLayout === 2
    ? [
        {
          arrayStride: 20,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x3" },
            { shaderLocation: 1, offset: 12, format: "float32x2" },
          ],
        },
        {
          arrayStride: instanceStrideBytes,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
            { shaderLocation: 6, offset: 128, format: "float32x4" },
          ],
        },
      ]
    : vertexLayout === 3
      ? [
          {
            arrayStride: 32,
            attributes: [
              { shaderLocation: 0, offset: 0, format: "float32x3" },
              { shaderLocation: 1, offset: 12, format: "float32x3" },
              { shaderLocation: 2, offset: 24, format: "float32x2" },
            ],
          },
          {
            arrayStride: instanceStrideBytes,
            stepMode: "instance",
            attributes: bindingMode === 2 || bindingMode === 3
              ? [
                  { shaderLocation: 3, offset: 0, format: "float32x4" },
                  { shaderLocation: 4, offset: 16, format: "float32x4" },
                  { shaderLocation: 5, offset: 32, format: "float32x4" },
                  { shaderLocation: 6, offset: 48, format: "float32x4" },
                  { shaderLocation: 7, offset: 64, format: "float32x4" },
                  { shaderLocation: 8, offset: 80, format: "float32x4" },
                  { shaderLocation: 9, offset: 96, format: "float32x4" },
                  { shaderLocation: 10, offset: 112, format: "float32x4" },
                  { shaderLocation: 11, offset: 128, format: "float32x4" },
                  { shaderLocation: 12, offset: 144, format: "float32x4" },
                ]
              : [
                  { shaderLocation: 3, offset: 0, format: "float32x4" },
                  { shaderLocation: 4, offset: 16, format: "float32x4" },
                  { shaderLocation: 5, offset: 32, format: "float32x4" },
                  { shaderLocation: 6, offset: 48, format: "float32x4" },
                  { shaderLocation: 7, offset: 128, format: "float32x4" },
                ],
          },
        ]
      : vertexLayout === 4
      ? [
          {
            arrayStride: 48,
            attributes: [
              { shaderLocation: 0, offset: 0, format: "float32x3" },
              { shaderLocation: 1, offset: 12, format: "float32x3" },
              { shaderLocation: 2, offset: 24, format: "float32x4" },
              { shaderLocation: 3, offset: 40, format: "float32x2" },
            ],
          },
          {
            arrayStride: instanceStrideBytes,
            stepMode: "instance",
            attributes: bindingMode === 2 || bindingMode === 3
              ? [
                  { shaderLocation: 4, offset: 0, format: "float32x4" },
                  { shaderLocation: 5, offset: 16, format: "float32x4" },
                  { shaderLocation: 6, offset: 32, format: "float32x4" },
                  { shaderLocation: 7, offset: 48, format: "float32x4" },
                  { shaderLocation: 8, offset: 64, format: "float32x4" },
                  { shaderLocation: 9, offset: 80, format: "float32x4" },
                  { shaderLocation: 10, offset: 96, format: "float32x4" },
                  { shaderLocation: 11, offset: 112, format: "float32x4" },
                  { shaderLocation: 12, offset: 128, format: "float32x4" },
                  { shaderLocation: 13, offset: 144, format: "float32x4" },
                ]
              : [
                  { shaderLocation: 4, offset: 0, format: "float32x4" },
                  { shaderLocation: 5, offset: 16, format: "float32x4" },
                  { shaderLocation: 6, offset: 32, format: "float32x4" },
                  { shaderLocation: 7, offset: 48, format: "float32x4" },
                  { shaderLocation: 8, offset: 128, format: "float32x4" },
                ],
          },
        ]
      : null;
  if (!vertexBuffers) return null;

  const opaque = ctx.device.createRenderPipeline({
    layout: materialPipelineLayout,
    vertex: {
      module,
      entryPoint: "vs_main",
      buffers: vertexBuffers,
    },
    fragment: {
      module,
      entryPoint: "fs_main",
      targets: [{ format: ctx.format }],
    },
    depthStencil: depthState,
    primitive: { topology: "triangle-list" },
  });

  const blend = ctx.device.createRenderPipeline({
    layout: materialPipelineLayout,
    vertex: {
      module,
      entryPoint: "vs_main",
      buffers: vertexBuffers,
    },
    fragment: {
      module,
      entryPoint: "fs_main",
      targets: [{
        format: ctx.format,
        blend: {
          color: { operation: "add", srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha" },
          alpha: { operation: "add", srcFactor: "one", dstFactor: "one-minus-src-alpha" },
        },
      }],
    },
    depthStencil: depthStateBlend,
    primitive: { topology: "triangle-list" },
  });
  webgpuCreates.pipelines += 2;
  return { opaque, blend, vertexLayout, bindingMode };
}

function createShadowPipelinesFromWgsl(ctx, wgslSource, vertexLayout, bindingMode = 1) {
  if (bindingMode === 2) {
    return null;
  }
  const module = ctx.device.createShaderModule({ code: wgslSource });
  const depthState = {
    format: "depth32float",
    depthWriteEnabled: true,
    depthCompare: "less-equal",
  };
  const pipelineLayout = bindingMode === 1
    ? ctx.device.createPipelineLayout({
        bindGroupLayouts: [ctx.quadBindGroupLayout],
      })
    : ctx.device.createPipelineLayout({
        bindGroupLayouts: [],
      });
  const vertexBuffers = vertexLayout === 0
    ? [
        {
          arrayStride: 16,
          attributes: [
            { shaderLocation: 0, offset: 0, format: "float32x2" },
            { shaderLocation: 1, offset: 8, format: "float32x2" },
          ],
        },
        {
          arrayStride: instanceStrideBytes,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
          ],
        },
      ]
    : vertexLayout === 2
      ? [
          {
            arrayStride: 20,
            attributes: [
              { shaderLocation: 0, offset: 0, format: "float32x3" },
              { shaderLocation: 1, offset: 12, format: "float32x2" },
            ],
          },
          {
            arrayStride: instanceStrideBytes,
            stepMode: "instance",
            attributes: [
              { shaderLocation: 2, offset: 0, format: "float32x4" },
              { shaderLocation: 3, offset: 16, format: "float32x4" },
              { shaderLocation: 4, offset: 32, format: "float32x4" },
              { shaderLocation: 5, offset: 48, format: "float32x4" },
            ],
          },
        ]
        : vertexLayout === 3
        ? [
            {
              arrayStride: 32,
              attributes: [
                { shaderLocation: 0, offset: 0, format: "float32x3" },
                { shaderLocation: 1, offset: 12, format: "float32x3" },
                { shaderLocation: 2, offset: 24, format: "float32x2" },
              ],
            },
            {
              arrayStride: instanceStrideBytes,
              stepMode: "instance",
              attributes: [
                { shaderLocation: 3, offset: 0, format: "float32x4" },
                { shaderLocation: 4, offset: 16, format: "float32x4" },
                { shaderLocation: 5, offset: 32, format: "float32x4" },
                { shaderLocation: 6, offset: 48, format: "float32x4" },
              ],
            },
          ]
        : vertexLayout === 4
        ? [
            {
              arrayStride: 48,
              attributes: [
                { shaderLocation: 0, offset: 0, format: "float32x3" },
                { shaderLocation: 1, offset: 12, format: "float32x3" },
                { shaderLocation: 2, offset: 24, format: "float32x4" },
                { shaderLocation: 3, offset: 40, format: "float32x2" },
              ],
            },
            {
              arrayStride: instanceStrideBytes,
              stepMode: "instance",
              attributes: [
                { shaderLocation: 4, offset: 0, format: "float32x4" },
                { shaderLocation: 5, offset: 16, format: "float32x4" },
                { shaderLocation: 6, offset: 32, format: "float32x4" },
                { shaderLocation: 7, offset: 48, format: "float32x4" },
              ],
            },
          ]
        : vertexLayout === 1
          ? [
              {
                arrayStride: 28,
                attributes: [
                  { shaderLocation: 0, offset: 0, format: "float32x3" },
                  { shaderLocation: 1, offset: 12, format: "float32x4" },
                ],
              },
              {
                arrayStride: instanceStrideBytes,
                stepMode: "instance",
                attributes: [
                  { shaderLocation: 2, offset: 0, format: "float32x4" },
                  { shaderLocation: 3, offset: 16, format: "float32x4" },
                  { shaderLocation: 4, offset: 32, format: "float32x4" },
                  { shaderLocation: 5, offset: 48, format: "float32x4" },
                ],
              },
            ]
          : null;
  if (!vertexBuffers) return null;
  const pipeline = ctx.device.createRenderPipeline({
    layout: pipelineLayout,
    vertex: {
      module,
      entryPoint: "vs_main",
      buffers: vertexBuffers,
    },
    depthStencil: depthState,
    primitive: { topology: "triangle-list" },
  });
  webgpuCreates.pipelines += 1;
  return { depthOnly: pipeline, vertexLayout, bindingMode };
}

function createPostProcessPipelinesFromWgsl(ctx, wgslSource) {
  const module = ctx.device.createShaderModule({ code: wgslSource });
  const opaque = ctx.device.createRenderPipeline({
    layout: ctx.postProcessPipelineLayout,
    vertex: {
      module,
      entryPoint: "vs_main",
    },
    fragment: {
      module,
      entryPoint: "fs_main",
      targets: [{ format: ctx.format }],
    },
    primitive: { topology: "triangle-list" },
  });

  const blend = ctx.device.createRenderPipeline({
    layout: ctx.postProcessPipelineLayout,
    vertex: {
      module,
      entryPoint: "vs_main",
    },
    fragment: {
      module,
      entryPoint: "fs_main",
      targets: [{
        format: ctx.format,
        blend: {
          color: { operation: "add", srcFactor: "src-alpha", dstFactor: "one-minus-src-alpha" },
          alpha: { operation: "add", srcFactor: "one", dstFactor: "one-minus-src-alpha" },
        },
      }],
    },
    primitive: { topology: "triangle-list" },
  });
  webgpuCreates.pipelines += 2;
  return { opaque, blend };
}

function createPostProcessTexture(ctx, width, height) {
  const texture = ctx.device.createTexture({
    size: { width, height },
    format: ctx.format,
    usage: GPUTextureUsage.RENDER_ATTACHMENT | GPUTextureUsage.TEXTURE_BINDING,
  });
  webgpuCreates.textures += 1;
  const view = texture.createView();
  webgpuCreates.textureViews += 1;
  const bindGroup = ctx.device.createBindGroup({
    layout: ctx.postProcessBindGroupLayout,
    entries: [
      { binding: 0, resource: ctx.postProcessSampler },
      { binding: 1, resource: view },
      {
        binding: 2,
        resource: {
          buffer: ctx.postProcessUniformBuffer,
          offset: 0,
          size: 80,
        },
      },
    ],
  });
  webgpuCreates.bindGroups += 1;
  return { texture, view, bindGroup, width, height };
}

function destroyPostProcessSlot(slot) {
  if (!slot) return;
  if (slot.texture) {
    slot.texture.destroy();
    webgpuDestroys.textures += 1;
  }
  webgpuDestroys.bindGroups += 1;
}

function ensurePostProcessSlot(ctx, slotIndex) {
  while (ctx.postProcessSlots.length <= slotIndex) {
    ctx.postProcessSlots.push(null);
  }
  const width = ctx.canvas.width || 1;
  const height = ctx.canvas.height || 1;
  const slot = ctx.postProcessSlots[slotIndex];
  if (!slot || slot.width !== width || slot.height !== height) {
    if (slot) {
      destroyPostProcessSlot(slot);
    }
    ctx.postProcessSlots[slotIndex] = createPostProcessTexture(ctx, width, height);
    if (ctx.shadowSlot === slotIndex) {
      ctx.shadowBindGroup = null;
    }
  }
  return ctx.postProcessSlots[slotIndex];
}

function ensureShadowMapSlot(ctx, slotIndex, width, height) {
  while (ctx.shadowMapSlots.length <= slotIndex) {
    ctx.shadowMapSlots.push(null);
  }
  const resolvedWidth = Math.max(1, width || 1);
  const resolvedHeight = Math.max(1, height || 1);
  const slot = ctx.shadowMapSlots[slotIndex];
  if (!slot || slot.width !== resolvedWidth || slot.height !== resolvedHeight) {
    if (slot) {
      destroyShadowMapSlot(slot);
    }
    ctx.shadowMapSlots[slotIndex] = createShadowMapSlot(ctx, resolvedWidth, resolvedHeight);
    if (ctx.shadowSlot === slotIndex) {
      ctx.shadowBindGroup = null;
    }
  }
  return ctx.shadowMapSlots[slotIndex];
}

function isSurfaceTargetSlot(slot) {
  return slot === -1 || slot === 0xffffffff;
}

function endCurrentPass(ctx) {
  if (!ctx.pass) return;
  ctx.pass.end();
  ctx.pass = null;
}

function beginRenderPass(ctx, view, clearValue, depthView, loadColor = false) {
  endCurrentPass(ctx);
  const descriptor = {
    colorAttachments: view ? [{
      view,
      loadOp: loadColor ? "load" : "clear",
      storeOp: "store",
      clearValue,
    }] : [],
  };
  if (depthView) {
    descriptor.depthStencilAttachment = {
      view: depthView,
      depthLoadOp: "clear",
      depthStoreOp: "store",
      depthClearValue: 1.0,
    };
  }
  ctx.pass = ctx.encoder.beginRenderPass(descriptor);
  webgpuCreates.renderPasses += 1;
}

function createContext(canvas, enableValidation) {
  const context = canvas.getContext("webgpu");
  const format = navigator.gpu.getPreferredCanvasFormat();
  const size = resizeCanvas(canvas);
  context.configure({
    device,
    format,
    alphaMode: "premultiplied",
  });

  const ctx = {
    device,
    queue: device.queue,
    canvas,
    context,
    format,
    meshes: [null],
    meshFree: [],
    shaders: [null],
    shaderFree: [],
    postProcessShaders: [null],
    postProcessShaderFree: [],
    textures: [null],
    samplers: [null],
    materials: [null],
    postProcessSlots: [],
    shadowMapSlots: [],
    instanceBufferSize: 512 * 1024,
    instanceOffset: 0,
    depthTexture: null,
    depthView: null,
    surfaceView: null,
    inFrame: false,
    errorScopeDepth: 0,
    enableValidation: Boolean(enableValidation),
    shadowBindGroup: null,
    shadowSlot: 0xffffffff,
    sceneEnvironmentBindGroup: null,
    sceneEnvironmentSampler: null,
    defaultSceneEnvironment: null,
  };

  createPipelines(ctx);
  createDepthTexture(ctx, size.framebufferWidth, size.framebufferHeight);

  ctx.instanceBuffer = device.createBuffer({
    size: ctx.instanceBufferSize,
    usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
  });
  webgpuCreates.buffers += 1;

  const triVerts = new Float32Array([
    0.0, 0.6, 1.0, 0.0, 0.0,
    -0.6, -0.6, 0.0, 1.0, 0.0,
    0.6, -0.6, 0.0, 0.0, 1.0,
  ]);
  ctx.triangleVertexBuffer = createBufferWithData(
    device,
    triVerts,
    GPUBufferUsage.VERTEX
  );

  return ctx;
}

function recordWebGpuError(kind, err) {
  if (!err) return;
  if (kind === "validation") {
    webgpuErrors.validation += 1;
  } else if (kind === "out-of-memory") {
    webgpuErrors.outOfMemory += 1;
  } else if (kind === "internal") {
    webgpuErrors.internal += 1;
  }
  console.error(`[phasor] webgpu ${kind} error`, err.message || err);
}

function shouldPauseSimulation() {
  if (!pauseOnGpuError) return false;
  if (deviceLost) return true;
  if (webgpuErrors.outOfMemory > 0) return true;
  if (webgpuErrors.internal > 0) return true;
  return false;
}

function shouldRecoverSimulation() {
  if (!enableRecovery) return false;
  if (!deviceLost) return false;
  if (recoveringDevice) return false;
  if (gpuFramesInFlight > 0) return false;
  return true;
}

function scheduleNextFrame(frame) {
  lastFrameScheduledAtMs = performance.now();
  if (useVsync) {
    requestAnimationFrame(frame);
  } else {
    setTimeout(frame, 0);
  }
}

function resetWebgpuErrors() {
  webgpuErrors.validation = 0;
  webgpuErrors.outOfMemory = 0;
  webgpuErrors.internal = 0;
}

async function initDevice() {
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    throw new Error("WebGPU adapter unavailable");
  }
  const newDevice = await adapter.requestDevice();
  newDevice.addEventListener("uncapturederror", (event) => {
    const err = event.error;
    const msg = err && err.message ? err.message : String(err);
    console.error("[phasor] webgpu uncaptured error", msg);
  });
  newDevice.lost.then((info) => {
    handleDeviceLost(info, newDevice).catch((err) => {
      console.error("[phasor] webgpu device loss handler failed", err);
    });
  });
  device = newDevice;
  deviceLost = false;
  resetWebgpuErrors();
  return newDevice;
}

async function handleDeviceLost(info, lostDevice) {
  if (lostDevice !== device) return;
  deviceLost = true;
  queueWaitPending = false;
  gpuFramesInFlight = 0;
  console.error("[phasor] webgpu device lost", info);
}

async function recoverWebGpu() {
  if (recoveringDevice) return;
  recoveringDevice = true;
  simulationPaused = true;
  const hint = document.querySelector(".hint");
  if (hint) hint.textContent = "WebGPU: recovering device";

  try {
    if (wasm && wasm.exports && wasm.exports.wasmOnDeviceLost && wasmApp) {
      try {
        wasm.exports.wasmOnDeviceLost(wasmApp);
      } catch (err) {
        console.error("[phasor] wasmOnDeviceLost error", err);
      }
    }

    for (const ctx of ctxs.values()) {
      destroyContextResources(ctx);
    }
    ctxs.clear();
    nextCtxId = 1;
    gpuFramesInFlight = 0;
    queueWaitPending = false;

    await initDevice();
    await loadShaders();

    if (wasm && wasm.exports && wasm.exports.wasmOnDeviceRestored && wasmApp) {
      try {
        wasm.exports.wasmOnDeviceRestored(wasmApp);
      } catch (err) {
        console.error("[phasor] wasmOnDeviceRestored error", err);
      }
    }

    const canvas = document.querySelector("#canvas");
    if (canvas && wasm && wasm.exports && wasm.exports.wasmResize) {
      const size = resizeCanvas(canvas);
      wasm.exports.wasmResize(
        wasmApp,
        size.logicalWidth,
        size.logicalHeight,
        size.framebufferWidth,
        size.framebufferHeight,
      );
    }

    simulationPaused = false;
    if (hint) hint.textContent = "";
    if (resumeFrameLoop) resumeFrameLoop();
  } catch (err) {
    console.error("[phasor] webgpu recovery failed", err);
    if (hint) hint.textContent = "WebGPU: recovery failed (see console)";
  } finally {
    recoveringDevice = false;
  }
}

function destroyContextResources(ctx) {
  if (ctx.pass) {
    try { ctx.pass.end(); } catch (_) {}
    ctx.pass = null;
  }
  if (ctx.encoder) {
    try { ctx.encoder.finish(); } catch (_) {}
    ctx.encoder = null;
  }
  ctx.surfaceView = null;
  if (ctx.instanceBuffer) {
    ctx.instanceBuffer.destroy();
    webgpuDestroys.buffers += 1;
    ctx.instanceBuffer = null;
  }
  if (ctx.postProcessUniformBuffer) {
    ctx.postProcessUniformBuffer.destroy();
    webgpuDestroys.buffers += 1;
    ctx.postProcessUniformBuffer = null;
  }
  if (ctx.triangleVertexBuffer) {
    ctx.triangleVertexBuffer.destroy();
    webgpuDestroys.buffers += 1;
    ctx.triangleVertexBuffer = null;
  }
  if (ctx.quadVertexBuffer) {
    ctx.quadVertexBuffer.destroy();
    webgpuDestroys.buffers += 1;
    ctx.quadVertexBuffer = null;
  }
  if (ctx.quadIndexBuffer) {
    ctx.quadIndexBuffer.destroy();
    webgpuDestroys.buffers += 1;
    ctx.quadIndexBuffer = null;
  }
  if (ctx.depthTexture) {
    ctx.depthTexture.destroy();
    webgpuDestroys.textures += 1;
    ctx.depthTexture = null;
    ctx.depthView = null;
  }

  for (let i = 1; i < ctx.meshes.length; i += 1) {
    const mesh = ctx.meshes[i];
    if (!mesh) continue;
    if (mesh.vertexBuffer) {
      mesh.vertexBuffer.destroy();
      webgpuDestroys.buffers += 1;
    }
    if (mesh.indexBuffer) {
      mesh.indexBuffer.destroy();
      webgpuDestroys.buffers += 1;
    }
    ctx.meshes[i] = null;
  }
  ctx.meshFree.length = 0;

  for (let i = 1; i < ctx.shaders.length; i += 1) {
    const shader = ctx.shaders[i];
    if (!shader) continue;
    webgpuDestroys.pipelines += 2;
    ctx.shaders[i] = null;
  }
  ctx.shaderFree.length = 0;

  for (let i = 1; i < ctx.postProcessShaders.length; i += 1) {
    const shader = ctx.postProcessShaders[i];
    if (!shader) continue;
    webgpuDestroys.pipelines += 2;
    ctx.postProcessShaders[i] = null;
  }
  ctx.postProcessShaderFree.length = 0;

  for (let i = 1; i < ctx.textures.length; i += 1) {
    const tex = ctx.textures[i];
    if (!tex) continue;
    if (tex.texture) {
      tex.texture.destroy();
      webgpuDestroys.textures += 1;
    }
    ctx.textures[i] = null;
  }

  for (let i = 1; i < ctx.samplers.length; i += 1) {
    const sampler = ctx.samplers[i];
    if (!sampler) continue;
    webgpuDestroys.samplers += 1;
    ctx.samplers[i] = null;
  }

  for (let i = 1; i < ctx.materials.length; i += 1) {
    const mat = ctx.materials[i];
    if (!mat) continue;
    // BindGroup doesn't have a destroy method; rely on GC.
    webgpuDestroys.bindGroups += 1;
    ctx.materials[i] = null;
  }

  for (let i = 0; i < ctx.postProcessSlots.length; i += 1) {
    if (!ctx.postProcessSlots[i]) continue;
    destroyPostProcessSlot(ctx.postProcessSlots[i]);
    ctx.postProcessSlots[i] = null;
  }
  ctx.postProcessSlots.length = 0;
  for (let i = 0; i < ctx.shadowMapSlots.length; i += 1) {
    if (!ctx.shadowMapSlots[i]) continue;
    destroyShadowMapSlot(ctx.shadowMapSlots[i]);
    ctx.shadowMapSlots[i] = null;
  }
  ctx.shadowMapSlots.length = 0;
  ctx.shadowBindGroup = null;
  ctx.shadowSlot = 0xffffffff;
  ctx.sceneEnvironmentBindGroup = null;

  if (ctx.postProcessSampler) {
    webgpuDestroys.samplers += 1;
    ctx.postProcessSampler = null;
  }
  if (ctx.sceneEnvironmentSampler) {
    webgpuDestroys.samplers += 1;
    ctx.sceneEnvironmentSampler = null;
  }
  if (ctx.defaultSceneEnvironment && ctx.defaultSceneEnvironment.texture) {
    ctx.defaultSceneEnvironment.texture.destroy();
    webgpuDestroys.textures += 1;
    ctx.defaultSceneEnvironment = null;
  }
}

function reconfigureContextSurface(ctx, reason) {
  if (!ctx || !ctx.context || !ctx.device || !ctx.canvas) return false;
  try {
    const size = resizeCanvas(ctx.canvas);
    ctx.context.configure({
      device: ctx.device,
      format: ctx.format,
      alphaMode: "premultiplied",
    });
    createDepthTexture(ctx, size.framebufferWidth, size.framebufferHeight);
    for (let i = 0; i < ctx.postProcessSlots.length; i += 1) {
      if (!ctx.postProcessSlots[i]) continue;
      destroyPostProcessSlot(ctx.postProcessSlots[i]);
      ctx.postProcessSlots[i] = null;
    }
    for (let i = 0; i < ctx.shadowMapSlots.length; i += 1) {
      if (!ctx.shadowMapSlots[i]) continue;
      destroyShadowMapSlot(ctx.shadowMapSlots[i]);
      ctx.shadowMapSlots[i] = null;
    }
    ctx.shadowBindGroup = null;
    ctx.shadowSlot = 0xffffffff;
    if (phasorDebug.lifecycleLogs) {
      console.log(
        "[phasor] webgpu surface reconfigured",
        reason,
        size.framebufferWidth,
        size.framebufferHeight,
      );
    }
    return true;
  } catch (err) {
    console.warn("[phasor] webgpu surface reconfigure failed", reason, err);
    return false;
  }
}

function ensureInstanceScratch(bytesNeeded) {
  if (instanceScratchBuffer && instanceScratchBytes >= bytesNeeded) {
    return;
  }
  instanceScratchBytes = Math.max(bytesNeeded, 256 * 1024);
  instanceScratchBuffer = new ArrayBuffer(instanceScratchBytes);
}

function countAliveSlots(list) {
  let alive = 0;
  for (let i = 1; i < list.length; i++) {
    if (list[i]) alive++;
  }
  return { alive, slots: Math.max(0, list.length - 1) };
}

function collectWebGpuStats(ctx) {
  const meshes = countAliveSlots(ctx.meshes);
  const textures = countAliveSlots(ctx.textures);
  const materials = countAliveSlots(ctx.materials);
  const samplers = countAliveSlots(ctx.samplers);
  return {
    meshesAlive: meshes.alive,
    meshesSlots: meshes.slots,
    meshesFree: ctx.meshFree.length,
    texturesAlive: textures.alive,
    texturesSlots: textures.slots,
    materialsAlive: materials.alive,
    materialsSlots: materials.slots,
    samplersAlive: samplers.alive,
    samplersSlots: samplers.slots,
  };
}

function scheduleQueueFence(ctx) {
  if (queueWaitPending || gpuFramesInFlight === 0) return;
  queueWaitPending = true;
  const submitStart = performance.now();
  const framesAtFence = gpuFramesInFlight;
  ctx.queue.onSubmittedWorkDone().then(() => {
    const waitMs = performance.now() - submitStart;
    lastQueueWaitMs = waitMs;
    if (waitMs > maxQueueWaitMs) maxQueueWaitMs = waitMs;
    gpuFramesInFlight = Math.max(0, gpuFramesInFlight - framesAtFence);
    queueWaitPending = false;
    scheduleQueueFence(ctx);
  }).catch(() => {
    gpuFramesInFlight = Math.max(0, gpuFramesInFlight - framesAtFence);
    queueWaitPending = false;
    scheduleQueueFence(ctx);
  });
}

const wasiBase = {
  args_sizes_get(argcPtr, argvBufSizePtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setUint32(argcPtr, 0, true);
    view.setUint32(argvBufSizePtr, 0, true);
    return 0;
  },
  args_get() {
    return 0;
  },
  environ_sizes_get(environCountPtr, environBufSizePtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setUint32(environCountPtr, 0, true);
    view.setUint32(environBufSizePtr, 0, true);
    return 0;
  },
  environ_get() {
    return 0;
  },
  fd_close() {
    return 0;
  },
  fd_seek(fd, offset, whence, newOffsetPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setBigUint64(newOffsetPtr, 0n, true);
    return 0;
  },
  fd_fdstat_get(fd, statPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    // Pretend it's a character device.
    view.setUint8(statPtr, 2);
    return 0;
  },
  fd_write(fd, iovsPtr, iovsLen, nwrittenPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    let written = 0;
    for (let i = 0; i < iovsLen; i += 1) {
      const base = view.getUint32(iovsPtr + i * 8, true);
      const len = view.getUint32(iovsPtr + i * 8 + 4, true);
      const bytes = new Uint8Array(memory.buffer, base, len);
      written += len;
      if (fd === 1 || fd === 2) {
        console.log(textDecoder.decode(bytes));
      }
    }
    view.setUint32(nwrittenPtr, written, true);
    return 0;
  },
  fd_read(fd, iovsPtr, iovsLen, nreadPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setUint32(nreadPtr, 0, true);
    return 0;
  },
  fd_prestat_get(fd, prestatPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setUint8(prestatPtr, 0);
    view.setUint32(prestatPtr + 4, 0, true);
    return 0;
  },
  fd_prestat_dir_name() {
    return 0;
  },
  path_create_directory() {
    return 0;
  },
  path_remove_directory() {
    return 0;
  },
  path_unlink_file() {
    return 0;
  },
  path_rename() {
    return 0;
  },
  path_readlink(fd, pathPtr, pathLen, bufPtr, bufLen, outLenPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setUint32(outLenPtr, 0, true);
    return 0;
  },
  path_filestat_get(fd, flags, pathPtr, pathLen, bufPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    // Zero out the filestat struct.
    for (let i = 0; i < 64; i += 4) {
      view.setUint32(bufPtr + i, 0, true);
    }
    return 0;
  },
  path_open(
    fd,
    dirflags,
    pathPtr,
    pathLen,
    oflags,
    fsRightsBase,
    fsRightsInheriting,
    fsFlags,
    fdOutPtr,
  ) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setUint32(fdOutPtr, 3, true);
    return 0;
  },
  fd_readdir(fd, bufPtr, bufLen, cookie, outLenPtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    view.setUint32(outLenPtr, 0, true);
    return 0;
  },
  clock_time_get(clockId, precision, timePtr) {
    if (!memory) return 0;
    const view = new DataView(memory.buffer);
    const nowMs = performance.timeOrigin + performance.now();
    const now = BigInt(Math.floor(nowMs * 1000000));
    view.setBigUint64(timePtr, now, true);
    return 0;
  },
  random_get(bufPtr, bufLen) {
    if (!memory) return 0;
    const bytes = new Uint8Array(memory.buffer, bufPtr, bufLen);
    crypto.getRandomValues(bytes);
    return 0;
  },
  proc_exit(code) {
    throw new Error(`WASI exit ${code}`);
  },
};

const wasi = new Proxy(wasiBase, {
  get(target, prop) {
    if (typeof prop === "symbol" || prop in target) {
      return target[prop];
    }
    return () => 0;
  },
});

const imports = {
  wasi_snapshot_preview1: wasi,
  env: {
    ...joltEnv.imports,
    wasm_memory_bytes() {
      if (!memory) return 0;
      return memory.buffer.byteLength;
    },
    wasm_js_heap(outUsedPtr, outTotalPtr) {
      const view = getMemoryView();
      if (!performance || !performance.memory) {
        view.setUint32(outUsedPtr, 0, true);
        view.setUint32(outTotalPtr, 0, true);
        return;
      }
      const mem = performance.memory;
      view.setUint32(outUsedPtr, mem.usedJSHeapSize >>> 0, true);
      view.setUint32(outTotalPtr, mem.totalJSHeapSize >>> 0, true);
    },
    wasmSetMouseCapture(enabled) {
      wantsMouseCapture = Boolean(enabled);
      const canvas = document.querySelector("#canvas");
      if (!canvas) return;
      if (wantsMouseCapture) {
        if (document.pointerLockElement !== canvas && canvas.requestPointerLock) {
          canvas.requestPointerLock().catch(() => {});
        }
      } else if (document.pointerLockElement && document.exitPointerLock) {
        document.exitPointerLock();
      }
    },
    wasm_audio_counts(outBuffersPtr, outActivePtr) {
      const view = getMemoryView();
      view.setUint32(outBuffersPtr, soundBuffers.size, true);
      view.setUint32(outActivePtr, activeSounds.size, true);
    },
    webgpu_canvas_size(canvasPtr, canvasLen, outW, outH) {
      const id = readString(canvasPtr, canvasLen);
      const canvas = document.querySelector(id);
      const size = resizeCanvas(canvas);
      const view = getMemoryView();
      view.setUint32(outW, size.framebufferWidth, true);
      view.setUint32(outH, size.framebufferHeight, true);
    },
    webgpu_init(canvasPtr, canvasLen, enableValidation) {
      const id = readString(canvasPtr, canvasLen);
      const canvas = document.querySelector(id);
      if (!canvas) {
        return 0;
      }
      const ctx = createContext(canvas, enableValidation);
      const ctxId = nextCtxId++;
      ctxs.set(ctxId, ctx);
      return ctxId;
    },
    webgpu_deinit(ctxId) {
      const ctx = ctxs.get(ctxId);
      if (ctx) {
        destroyContextResources(ctx);
      }
      ctxs.delete(ctxId);
    },
    webgpu_resize(ctxId, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      resizeCalls += 1;
      ctx.canvas.width = width;
      ctx.canvas.height = height;
      reconfigureContextSurface(ctx, "webgpu_resize");
    },
    webgpu_begin_frame(ctxId, r, g, b, a) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      frameIndex += 1;
      if (ctx.inFrame) {
        console.warn("[phasor] webgpu_begin_frame called while already in-frame");
      }
      ctx.inFrame = true;
      webgpuFramesBegun += 1;
      if (!deviceLost && ctx.enableValidation) {
        ctx.device.pushErrorScope("validation");
        ctx.device.pushErrorScope("out-of-memory");
        ctx.device.pushErrorScope("internal");
        ctx.errorScopeDepth += 3;
      }
      ctx.instanceOffset = 0;
      try {
        const encoder = ctx.device.createCommandEncoder();
        webgpuCreates.commandEncoders += 1;
        ctx.encoder = encoder;
        ctx.surfaceView = ctx.context.getCurrentTexture().createView();
        webgpuCreates.textureViews += 1;
      } catch (err) {
        ctx.inFrame = false;
        ctx.surfaceView = null;
        if (ctx.enableValidation && ctx.errorScopeDepth >= 3) {
          ctx.errorScopeDepth -= 3;
          ctx.device.popErrorScope().catch(() => {});
          ctx.device.popErrorScope().catch(() => {});
          ctx.device.popErrorScope().catch(() => {});
        }
        reconfigureContextSurface(ctx, "begin_frame_exception");
        throw err;
      }
    },
    webgpu_begin_scene_pass(ctxId, targetSlot, r, g, b, a) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.encoder) return;
      const target = isSurfaceTargetSlot(targetSlot) ? { view: ctx.surfaceView } : ensurePostProcessSlot(ctx, targetSlot);
      if (!target || !target.view) return;
      beginRenderPass(ctx, target.view, { r, g, b, a }, ctx.depthView);
    },
    webgpu_begin_scene_pass_load(ctxId, targetSlot) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.encoder) return;
      const target = isSurfaceTargetSlot(targetSlot) ? { view: ctx.surfaceView } : ensurePostProcessSlot(ctx, targetSlot);
      if (!target || !target.view) return;
      beginRenderPass(ctx, target.view, { r: 0, g: 0, b: 0, a: 0 }, ctx.depthView, true);
    },
    webgpu_begin_shadow_pass(ctxId, targetSlot) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.encoder) return;
      const target = ctx.shadowMapSlots[targetSlot >>> 0];
      if (!target || !target.view) return;
      beginRenderPass(ctx, null, { r: 0, g: 0, b: 0, a: 0 }, target.view);
    },
    webgpu_begin_post_process_pass(ctxId, targetSlot, r, g, b, a) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.encoder) return;
      const target = isSurfaceTargetSlot(targetSlot) ? { view: ctx.surfaceView } : ensurePostProcessSlot(ctx, targetSlot);
      if (!target || !target.view) return;
      beginRenderPass(ctx, target.view, { r, g, b, a }, null);
    },
    webgpu_draw_triangle(ctxId) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.pass) return;
      ctx.pass.setPipeline(ctx.trianglePipeline);
      ctx.pass.setVertexBuffer(0, ctx.triangleVertexBuffer);
      ctx.pass.draw(3, 1, 0, 0);
    },
    webgpu_set_viewport_scissor(ctxId, x, y, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.pass) return;
      const vx = Math.max(0, x);
      const vy = Math.max(0, y);
      const vw = Math.max(0, width);
      const vh = Math.max(0, height);
      ctx.pass.setViewport(vx, vy, vw, vh, 0.0, 1.0);
      ctx.pass.setScissorRect(
        Math.floor(vx),
        Math.floor(vy),
        Math.floor(vw),
        Math.floor(vh),
      );
    },
    webgpu_draw_textured_quad(ctxId, meshHandle, materialHandle, instancePtr, blend) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || deviceLost || recoveringDevice || !ctx.pass) return;
      const mesh = ctx.meshes[meshHandle];
      const material = ctx.materials[materialHandle];
      if (!mesh || !material) return;
      const pipeline = mesh.vertexLayout === 1
        ? (blend ? ctx.quadPipelineBlend : ctx.quadPipelineOpaque)
        : mesh.vertexLayout === 2
          ? (blend ? ctx.meshTexturedPipelineBlend : ctx.meshTexturedPipelineOpaque)
          : null;
      if (!pipeline) return;
      const instanceData = new Float32Array(memory.buffer, instancePtr, instanceFloatCount);
      const stride = instanceStrideBytes;
      const alignment = 256;
      let offset = Math.ceil(ctx.instanceOffset / alignment) * alignment;
      if (offset + stride > ctx.instanceBufferSize) {
        offset = 0;
      }
      ctx.instanceOffset = offset + stride;
      ctx.queue.writeBuffer(ctx.instanceBuffer, offset, instanceData);

      ctx.pass.setPipeline(pipeline);
      ctx.pass.setBindGroup(0, material.bindGroup);
      ctx.pass.setVertexBuffer(0, mesh.vertexBuffer);
      ctx.pass.setVertexBuffer(1, ctx.instanceBuffer, offset, stride);
      ctx.pass.setIndexBuffer(mesh.indexBuffer, "uint16");
      ctx.pass.drawIndexed(mesh.indexCount, 1, 0, 0, 0);
    },
    webgpu_draw_textured_quads(ctxId, meshHandle, materialHandle, instancePtr, instanceCount, blend) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || deviceLost || recoveringDevice || !ctx.pass) return;
      const mesh = ctx.meshes[meshHandle];
      const material = ctx.materials[materialHandle];
      if (!mesh || !material) return;
      const pipeline = mesh.vertexLayout === 1
        ? (blend ? ctx.quadPipelineBlend : ctx.quadPipelineOpaque)
        : mesh.vertexLayout === 2
          ? (blend ? ctx.meshTexturedPipelineBlend : ctx.meshTexturedPipelineOpaque)
          : null;
      if (!pipeline) return;
      if (!instanceCount) return;
      const stride = instanceStrideBytes;
      const alignment = 256;
      const byteLength = instanceCount * stride;
      if (byteLength > ctx.instanceBufferSize) {
        console.warn("[phasor] instance buffer overflow", byteLength, ctx.instanceBufferSize);
        return;
      }
      const instanceData = new Float32Array(memory.buffer, instancePtr, instanceCount * instanceFloatCount);
      ensureInstanceScratch(byteLength);
      const scratch = new Uint8Array(instanceScratchBuffer, 0, byteLength);
      scratch.set(new Uint8Array(instanceData.buffer, instanceData.byteOffset, byteLength));
      let offset = Math.ceil(ctx.instanceOffset / alignment) * alignment;
      if (offset + byteLength > ctx.instanceBufferSize) {
        offset = 0;
      }
      ctx.instanceOffset = offset + byteLength;
      ctx.queue.writeBuffer(ctx.instanceBuffer, offset, scratch);

      ctx.pass.setPipeline(pipeline);
      ctx.pass.setBindGroup(0, material.bindGroup);
      ctx.pass.setVertexBuffer(0, mesh.vertexBuffer);
      ctx.pass.setVertexBuffer(1, ctx.instanceBuffer, offset, byteLength);
      ctx.pass.setIndexBuffer(mesh.indexBuffer, "uint16");
      ctx.pass.drawIndexed(mesh.indexCount, instanceCount, 0, 0, 0);
    },
    webgpu_draw_colored_meshes(ctxId, meshHandle, shaderHandle, instancePtr, instanceCount, blend) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || deviceLost || recoveringDevice || !ctx.pass) return;
      const mesh = ctx.meshes[meshHandle];
      const shader = ctx.shaders[shaderHandle];
      if (!mesh || !shader) return;
      if (mesh.vertexLayout !== 3) return;
      if (!instanceCount) return;
      const stride = instanceStrideBytes;
      const alignment = 256;
      const byteLength = instanceCount * stride;
      if (byteLength > ctx.instanceBufferSize) {
        console.warn("[phasor] instance buffer overflow", byteLength, ctx.instanceBufferSize);
        return;
      }
      const instanceData = new Float32Array(memory.buffer, instancePtr, instanceCount * instanceFloatCount);
      ensureInstanceScratch(byteLength);
      const scratch = new Uint8Array(instanceScratchBuffer, 0, byteLength);
      scratch.set(new Uint8Array(instanceData.buffer, instanceData.byteOffset, byteLength));
      let offset = Math.ceil(ctx.instanceOffset / alignment) * alignment;
      if (offset + byteLength > ctx.instanceBufferSize) {
        offset = 0;
      }
      ctx.instanceOffset = offset + byteLength;
      ctx.queue.writeBuffer(ctx.instanceBuffer, offset, scratch);

      const pipeline = blend ? shader.blend : shader.opaque;
      ctx.pass.setPipeline(pipeline);
      ctx.pass.setVertexBuffer(0, mesh.vertexBuffer);
      ctx.pass.setVertexBuffer(1, ctx.instanceBuffer, offset, byteLength);
      ctx.pass.setIndexBuffer(mesh.indexBuffer, "uint16");
      ctx.pass.drawIndexed(mesh.indexCount, instanceCount, 0, 0, 0);
    },
    webgpu_draw_textured_meshes_with_shader(ctxId, meshHandle, materialHandle, shaderHandle, instancePtr, instanceCount, blend) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || deviceLost || recoveringDevice || !ctx.pass) return;
      const mesh = ctx.meshes[meshHandle];
      const material = ctx.materials[materialHandle];
      const shader = ctx.shaders[shaderHandle];
      if (!mesh || !material || !shader) return;
      if (mesh.vertexLayout !== 1 && mesh.vertexLayout !== 2 && mesh.vertexLayout !== 4) return;
      if (!instanceCount) return;
      const stride = instanceStrideBytes;
      const alignment = 256;
      const byteLength = instanceCount * stride;
      if (byteLength > ctx.instanceBufferSize) {
        console.warn("[phasor] instance buffer overflow", byteLength, ctx.instanceBufferSize);
        return;
      }
      const instanceData = new Float32Array(memory.buffer, instancePtr, instanceCount * instanceFloatCount);
      ensureInstanceScratch(byteLength);
      const scratch = new Uint8Array(instanceScratchBuffer, 0, byteLength);
      scratch.set(new Uint8Array(instanceData.buffer, instanceData.byteOffset, byteLength));
      let offset = Math.ceil(ctx.instanceOffset / alignment) * alignment;
      if (offset + byteLength > ctx.instanceBufferSize) {
        offset = 0;
      }
      ctx.instanceOffset = offset + byteLength;
      ctx.queue.writeBuffer(ctx.instanceBuffer, offset, scratch);

      const pipeline = blend ? shader.blend : shader.opaque;
      ctx.pass.setPipeline(pipeline);
      if (shader.bindingMode === 2) {
        ctx.pass.setBindGroup(0, material.sceneBindGroup);
        if (ctx.shadowBindGroup) {
          ctx.pass.setBindGroup(1, ctx.shadowBindGroup);
        }
      } else if (shader.bindingMode === 3) {
        ctx.pass.setBindGroup(0, material.sceneEnvironmentMaterialBindGroup);
        ctx.pass.setBindGroup(1, ctx.sceneEnvironmentBindGroup);
        if (ctx.shadowBindGroup) {
          ctx.pass.setBindGroup(2, ctx.shadowBindGroup);
        }
      } else {
        ctx.pass.setBindGroup(0, material.bindGroup);
      }
      ctx.pass.setVertexBuffer(0, mesh.vertexBuffer);
      ctx.pass.setVertexBuffer(1, ctx.instanceBuffer, offset, byteLength);
      ctx.pass.setIndexBuffer(mesh.indexBuffer, "uint16");
      ctx.pass.drawIndexed(mesh.indexCount, instanceCount, 0, 0, 0);
    },
    webgpu_draw_shadow_colored_meshes(ctxId, meshHandle, shaderHandle, instancePtr, instanceCount) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || deviceLost || recoveringDevice || !ctx.pass) return;
      const mesh = ctx.meshes[meshHandle];
      const shader = ctx.shaders[shaderHandle];
      if (!mesh || !shader || !shader.depthOnly) return;
      if (mesh.vertexLayout !== 3) return;
      if (!instanceCount) return;
      const stride = instanceStrideBytes;
      const alignment = 256;
      const byteLength = instanceCount * stride;
      if (byteLength > ctx.instanceBufferSize) return;
      const instanceData = new Float32Array(memory.buffer, instancePtr, instanceCount * instanceFloatCount);
      ensureInstanceScratch(byteLength);
      const scratch = new Uint8Array(instanceScratchBuffer, 0, byteLength);
      scratch.set(new Uint8Array(instanceData.buffer, instanceData.byteOffset, byteLength));
      let offset = Math.ceil(ctx.instanceOffset / alignment) * alignment;
      if (offset + byteLength > ctx.instanceBufferSize) {
        offset = 0;
      }
      ctx.instanceOffset = offset + byteLength;
      ctx.queue.writeBuffer(ctx.instanceBuffer, offset, scratch);

      ctx.pass.setPipeline(shader.depthOnly);
      ctx.pass.setVertexBuffer(0, mesh.vertexBuffer);
      ctx.pass.setVertexBuffer(1, ctx.instanceBuffer, offset, byteLength);
      ctx.pass.setIndexBuffer(mesh.indexBuffer, "uint16");
      ctx.pass.drawIndexed(mesh.indexCount, instanceCount, 0, 0, 0);
    },
    webgpu_draw_shadow_textured_meshes_with_shader(ctxId, meshHandle, materialHandle, shaderHandle, instancePtr, instanceCount) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || deviceLost || recoveringDevice || !ctx.pass) return;
      const mesh = ctx.meshes[meshHandle];
      const material = ctx.materials[materialHandle];
      const shader = ctx.shaders[shaderHandle];
      if (!mesh || !material || !shader || !shader.depthOnly) return;
      if (mesh.vertexLayout !== 1 && mesh.vertexLayout !== 2 && mesh.vertexLayout !== 4) return;
      if (!instanceCount) return;
      const stride = instanceStrideBytes;
      const alignment = 256;
      const byteLength = instanceCount * stride;
      if (byteLength > ctx.instanceBufferSize) return;
      const instanceData = new Float32Array(memory.buffer, instancePtr, instanceCount * instanceFloatCount);
      ensureInstanceScratch(byteLength);
      const scratch = new Uint8Array(instanceScratchBuffer, 0, byteLength);
      scratch.set(new Uint8Array(instanceData.buffer, instanceData.byteOffset, byteLength));
      let offset = Math.ceil(ctx.instanceOffset / alignment) * alignment;
      if (offset + byteLength > ctx.instanceBufferSize) {
        offset = 0;
      }
      ctx.instanceOffset = offset + byteLength;
      ctx.queue.writeBuffer(ctx.instanceBuffer, offset, scratch);

      ctx.pass.setPipeline(shader.depthOnly);
      if (shader.bindingMode === 1) {
        ctx.pass.setBindGroup(0, material.bindGroup);
      }
      ctx.pass.setVertexBuffer(0, mesh.vertexBuffer);
      ctx.pass.setVertexBuffer(1, ctx.instanceBuffer, offset, byteLength);
      ctx.pass.setIndexBuffer(mesh.indexBuffer, "uint16");
      ctx.pass.drawIndexed(mesh.indexCount, instanceCount, 0, 0, 0);
    },
    webgpu_set_scene_uniforms(ctxId, uniformsPtr, uniformsLen) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.sceneUniformBuffer) return;
      const bytes = new Uint8Array(memory.buffer, uniformsPtr, uniformsLen);
      ctx.queue.writeBuffer(ctx.sceneUniformBuffer, 0, bytes);
    },
    webgpu_set_shadow_state(ctxId, slot, uniformsPtr, uniformsLen) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.shadowUniformBuffer) return;
      const bytes = new Uint8Array(memory.buffer, uniformsPtr, uniformsLen);
      ctx.queue.writeBuffer(ctx.shadowUniformBuffer, 0, bytes);
      const slotIndex = Number(slot >>> 0);
      const shadowSlot = ctx.shadowMapSlots[slotIndex];
      if (!shadowSlot) return;
      if (!ctx.shadowBindGroup || ctx.shadowSlot !== slotIndex) {
        ctx.shadowBindGroup = ctx.device.createBindGroup({
          layout: ctx.shadowBindGroupLayout,
          entries: [
            {
              binding: 0,
              resource: {
                buffer: ctx.shadowUniformBuffer,
                offset: 0,
                size: shadowUniformsSize,
              },
            },
            { binding: 1, resource: ctx.shadowSampler },
            { binding: 2, resource: shadowSlot.view },
          ],
        });
        webgpuCreates.bindGroups += 1;
        ctx.shadowSlot = slotIndex;
      }
    },
    webgpu_draw_post_process(ctxId, shaderHandle, sourceSlot, uniformsPtr, blend) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || deviceLost || recoveringDevice || !ctx.pass) return;
      const shader = ctx.postProcessShaders[shaderHandle];
      const source = ctx.postProcessSlots[sourceSlot];
      if (!shader || !source) return;
      const uniforms = new Float32Array(memory.buffer, uniformsPtr, 20);
      const uniformBytes = new Uint8Array(uniforms.buffer, uniforms.byteOffset, 80);
      ctx.queue.writeBuffer(ctx.postProcessUniformBuffer, 0, uniformBytes);
      ctx.pass.setPipeline(blend ? shader.blend : shader.opaque);
      ctx.pass.setBindGroup(0, source.bindGroup);
      ctx.pass.draw(3, 1, 0, 0);
    },
    webgpu_end_frame(ctxId) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      if (!ctx.inFrame) {
        console.warn("[phasor] webgpu_end_frame called without begin_frame");
      }
      if (phasorDebug.hotPathWarnings) {
        const deltaBuffers = webgpuCreates.buffers - lastFrameCounts.buffers;
        const deltaTextures = webgpuCreates.textures - lastFrameCounts.textures;
        const deltaViews = webgpuCreates.textureViews - lastFrameCounts.textureViews;
        const deltaSamplers = webgpuCreates.samplers - lastFrameCounts.samplers;
        const deltaBindGroups = webgpuCreates.bindGroups - lastFrameCounts.bindGroups;
        const deltaPipelines = webgpuCreates.pipelines - lastFrameCounts.pipelines;
        const deltaEncoders = webgpuCreates.commandEncoders - lastFrameCounts.commandEncoders;
        const deltaPasses = webgpuCreates.renderPasses - lastFrameCounts.renderPasses;
        const depthRebuiltThisFrame = lastDepthRebuildFrame == frameIndex;
        if (deltaBuffers > 0 || deltaBindGroups > 0 || deltaPipelines > 0 || (deltaTextures > 0 && !depthRebuiltThisFrame)) {
          console.warn(
            "[phasor] webgpu per-frame allocations",
            "frame=" + frameIndex,
            "buffers=" + deltaBuffers,
            "textures=" + deltaTextures,
            "views=" + deltaViews,
            "samplers=" + deltaSamplers,
            "bindGroups=" + deltaBindGroups,
            "pipelines=" + deltaPipelines,
            "encoders=" + deltaEncoders,
            "passes=" + deltaPasses,
            "resize=" + resizeCalls,
            "depthRebuilds=" + depthRebuilds,
          );
        }
        lastFrameCounts.buffers = webgpuCreates.buffers;
        lastFrameCounts.textures = webgpuCreates.textures;
        lastFrameCounts.textureViews = webgpuCreates.textureViews;
        lastFrameCounts.samplers = webgpuCreates.samplers;
        lastFrameCounts.bindGroups = webgpuCreates.bindGroups;
        lastFrameCounts.pipelines = webgpuCreates.pipelines;
        lastFrameCounts.commandEncoders = webgpuCreates.commandEncoders;
        lastFrameCounts.renderPasses = webgpuCreates.renderPasses;
      }
      endCurrentPass(ctx);
      ctx.queue.submit([ctx.encoder.finish()]);
      gpuFramesInFlight += 1;
      scheduleQueueFence(ctx);
      ctx.pass = null;
      ctx.encoder = null;
      ctx.surfaceView = null;
      ctx.inFrame = false;
      webgpuFramesEnded += 1;
      if (deviceLost) return;
      if (ctx.enableValidation && ctx.errorScopeDepth >= 3) {
        ctx.errorScopeDepth -= 3;
        ctx.device.popErrorScope().then((err) => recordWebGpuError("internal", err)).catch(() => {});
        ctx.device.popErrorScope().then((err) => recordWebGpuError("out-of-memory", err)).catch(() => {});
        ctx.device.popErrorScope().then((err) => recordWebGpuError("validation", err)).catch(() => {});
      } else if (ctx.enableValidation && ctx.errorScopeDepth < 3) {
        console.warn("[phasor] webgpu_end_frame missing error scopes");
      }
    },
    webgpu_create_sampler(ctxId) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const sampler = ctx.device.createSampler({
        magFilter: "linear",
        minFilter: "linear",
        mipmapFilter: "linear",
        addressModeU: "clamp-to-edge",
        addressModeV: "clamp-to-edge",
        addressModeW: "clamp-to-edge",
      });
      webgpuCreates.samplers += 1;
      const handle = ctx.samplers.length;
      ctx.samplers.push(sampler);
      return handle;
    },
    webgpu_create_sampler_desc(ctxId, magFilter, minFilter, mipmapFilter, addressModeU, addressModeV, addressModeW) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const filters = ["nearest", "linear"];
      const addressModes = ["clamp-to-edge", "repeat", "mirror-repeat"];
      const sampler = ctx.device.createSampler({
        magFilter: filters[magFilter] || "linear",
        minFilter: filters[minFilter] || "linear",
        mipmapFilter: filters[mipmapFilter] || "linear",
        addressModeU: addressModes[addressModeU] || "clamp-to-edge",
        addressModeV: addressModes[addressModeV] || "clamp-to-edge",
        addressModeW: addressModes[addressModeW] || "clamp-to-edge",
      });
      webgpuCreates.samplers += 1;
      const handle = ctx.samplers.length;
      ctx.samplers.push(sampler);
      return handle;
    },
    webgpu_destroy_sampler(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.samplers[handle] = null;
      webgpuDestroys.samplers += 1;
    },
    webgpu_create_texture_rgba8(ctxId, _samplerHandle, dataPtr, dataLen, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const texture = ctx.device.createTexture({
        size: { width, height },
        format: "rgba8unorm-srgb",
        usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
      });
      webgpuCreates.textures += 1;
      const view = texture.createView();
      webgpuCreates.textureViews += 1;
      const bytesPerRow = width * 4;
      const alignedBpr = Math.ceil(bytesPerRow / 256) * 256;
      let data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      if (alignedBpr !== bytesPerRow) {
        const padded = new Uint8Array(alignedBpr * height);
        for (let row = 0; row < height; row++) {
          const srcOff = row * bytesPerRow;
          const dstOff = row * alignedBpr;
          padded.set(data.subarray(srcOff, srcOff + bytesPerRow), dstOff);
        }
        data = padded;
      }
      ctx.queue.writeTexture(
        { texture },
        data,
        { bytesPerRow: alignedBpr },
        { width, height }
      );
      const handle = ctx.textures.length;
      ctx.textures.push({ texture, view });
      return handle;
    },
    webgpu_create_texture_rgba8_linear(ctxId, _samplerHandle, dataPtr, dataLen, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const texture = ctx.device.createTexture({
        size: { width, height },
        format: "rgba8unorm",
        usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
      });
      webgpuCreates.textures += 1;
      const view = texture.createView();
      webgpuCreates.textureViews += 1;
      const bytesPerRow = width * 4;
      const alignedBpr = Math.ceil(bytesPerRow / 256) * 256;
      let data = new Uint8Array(memory.buffer, dataPtr, dataLen);
      if (alignedBpr !== bytesPerRow) {
        const padded = new Uint8Array(alignedBpr * height);
        for (let row = 0; row < height; row++) {
          const srcOff = row * bytesPerRow;
          const dstOff = row * alignedBpr;
          padded.set(data.subarray(srcOff, srcOff + bytesPerRow), dstOff);
        }
        data = padded;
      }
      ctx.queue.writeTexture(
        { texture },
        data,
        { bytesPerRow: alignedBpr },
        { width, height }
      );
      const handle = ctx.textures.length;
      ctx.textures.push({ texture, view });
      return handle;
    },
    webgpu_create_texture_rgba16f(ctxId, _samplerHandle, dataPtr, dataLen, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const texture = ctx.device.createTexture({
        size: { width, height },
        format: "rgba16float",
        usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
      });
      webgpuCreates.textures += 1;
      const view = texture.createView();
      webgpuCreates.textureViews += 1;
      const bytesPerRow = width * 8;
      const alignedBpr = Math.ceil(bytesPerRow / 256) * 256;
      const src = new Float32Array(memory.buffer, dataPtr, dataLen);
      const padded = new Uint16Array((alignedBpr / 2) * height);
      const pixelStride = 4;
      for (let row = 0; row < height; row += 1) {
        const srcRow = row * width * pixelStride;
        const dstRow = row * (alignedBpr / 2);
        for (let x = 0; x < width; x += 1) {
          const srcBase = srcRow + x * pixelStride;
          const dstBase = dstRow + x * pixelStride;
          padded[dstBase + 0] = float32ToFloat16(src[srcBase + 0]);
          padded[dstBase + 1] = float32ToFloat16(src[srcBase + 1]);
          padded[dstBase + 2] = float32ToFloat16(src[srcBase + 2]);
          padded[dstBase + 3] = float32ToFloat16(src[srcBase + 3]);
        }
      }
      ctx.queue.writeTexture(
        { texture },
        padded,
        { bytesPerRow: alignedBpr },
        { width, height }
      );
      const handle = ctx.textures.length;
      ctx.textures.push({ texture, view });
      return handle;
    },
    webgpu_destroy_texture(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const tex = ctx.textures[handle];
      if (tex && tex.texture) {
        tex.texture.destroy();
        webgpuDestroys.textures += 1;
      }
      ctx.textures[handle] = null;
    },
    webgpu_create_material(ctxId, textureHandle, samplerHandle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const texture = ctx.textures[textureHandle];
      const sampler = ctx.samplers[samplerHandle];
      if (!texture || !sampler) return 0;
      const bindGroup = ctx.device.createBindGroup({
        layout: ctx.quadBindGroupLayout,
        entries: [
          { binding: 0, resource: sampler },
          { binding: 1, resource: texture.view },
        ],
      });
      const sceneBindGroup = ctx.device.createBindGroup({
        layout: ctx.sceneBindGroupLayout,
        entries: [
          { binding: 0, resource: sampler },
          { binding: 1, resource: texture.view },
          {
            binding: 2,
            resource: {
              buffer: ctx.sceneUniformBuffer,
              offset: 0,
              size: sceneUniformsSize,
            },
          },
          { binding: 3, resource: texture.view },
          { binding: 4, resource: texture.view },
          { binding: 5, resource: texture.view },
        ],
      });
      const sceneEnvironmentMaterialBindGroup = ctx.device.createBindGroup({
        layout: ctx.sceneMaterialBindGroupLayout,
        entries: [
          { binding: 0, resource: sampler },
          { binding: 1, resource: texture.view },
          { binding: 2, resource: texture.view },
          { binding: 3, resource: texture.view },
          { binding: 4, resource: texture.view },
        ],
      });
      webgpuCreates.bindGroups += 3;
      const handle = ctx.materials.length;
      ctx.materials.push({ bindGroup, sceneBindGroup, sceneEnvironmentMaterialBindGroup });
      return handle;
    },
    webgpu_create_scene_material(ctxId, baseColorTextureHandle, metallicRoughnessTextureHandle, occlusionTextureHandle, normalTextureHandle, samplerHandle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const baseColor = ctx.textures[baseColorTextureHandle];
      const metallicRoughness = ctx.textures[metallicRoughnessTextureHandle];
      const occlusion = ctx.textures[occlusionTextureHandle];
      const normal = ctx.textures[normalTextureHandle];
      const sampler = ctx.samplers[samplerHandle];
      if (!baseColor || !metallicRoughness || !occlusion || !normal || !sampler) return 0;
      const bindGroup = ctx.device.createBindGroup({
        layout: ctx.quadBindGroupLayout,
        entries: [
          { binding: 0, resource: sampler },
          { binding: 1, resource: baseColor.view },
        ],
      });
      const sceneBindGroup = ctx.device.createBindGroup({
        layout: ctx.sceneBindGroupLayout,
        entries: [
          { binding: 0, resource: sampler },
          { binding: 1, resource: baseColor.view },
          {
            binding: 2,
            resource: {
              buffer: ctx.sceneUniformBuffer,
              offset: 0,
              size: sceneUniformsSize,
            },
          },
          { binding: 3, resource: metallicRoughness.view },
          { binding: 4, resource: occlusion.view },
          { binding: 5, resource: normal.view },
        ],
      });
      const sceneEnvironmentMaterialBindGroup = ctx.device.createBindGroup({
        layout: ctx.sceneMaterialBindGroupLayout,
        entries: [
          { binding: 0, resource: sampler },
          { binding: 1, resource: baseColor.view },
          { binding: 2, resource: metallicRoughness.view },
          { binding: 3, resource: occlusion.view },
          { binding: 4, resource: normal.view },
        ],
      });
      webgpuCreates.bindGroups += 3;
      const handle = ctx.materials.length;
      ctx.materials.push({ bindGroup, sceneBindGroup, sceneEnvironmentMaterialBindGroup });
      return handle;
    },
    webgpu_destroy_material(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.materials[handle] = null;
      webgpuDestroys.bindGroups += 3;
    },
    webgpu_set_scene_environment(ctxId, textureHandle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const texture = ctx.textures[textureHandle];
      if (!texture) return;
      ctx.sceneEnvironmentBindGroup = ctx.device.createBindGroup({
        layout: ctx.sceneEnvironmentBindGroupLayout,
        entries: [
          {
            binding: 0,
            resource: {
              buffer: ctx.sceneUniformBuffer,
              offset: 0,
              size: sceneUniformsSize,
            },
          },
          { binding: 1, resource: ctx.sceneEnvironmentSampler },
          { binding: 2, resource: texture.view },
        ],
      });
      webgpuCreates.bindGroups += 1;
    },
    webgpu_reset_scene_environment(ctxId) {
      const ctx = ctxs.get(ctxId);
      if (!ctx || !ctx.defaultSceneEnvironment) return;
      ctx.sceneEnvironmentBindGroup = ctx.device.createBindGroup({
        layout: ctx.sceneEnvironmentBindGroupLayout,
        entries: [
          {
            binding: 0,
            resource: {
              buffer: ctx.sceneUniformBuffer,
              offset: 0,
              size: sceneUniformsSize,
            },
          },
          { binding: 1, resource: ctx.sceneEnvironmentSampler },
          { binding: 2, resource: ctx.defaultSceneEnvironment.view },
        ],
      });
      webgpuCreates.bindGroups += 1;
    },
    webgpu_create_mesh(ctxId, vertexLayout, vPtr, vLen, iPtr, iLen) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const vertices = new Uint8Array(memory.buffer, vPtr, vLen);
      const indices = new Uint8Array(memory.buffer, iPtr, iLen);
      const vertexBuffer = createBufferWithData(ctx.device, vertices, GPUBufferUsage.VERTEX);
      const indexBuffer = createBufferWithData(ctx.device, indices, GPUBufferUsage.INDEX);
      const indexCount = iLen / 2;
      let handle = 0;
      if (ctx.meshFree.length > 0) {
        handle = ctx.meshFree.pop();
        ctx.meshes[handle] = {
          vertexBuffer,
          indexBuffer,
          indexCount,
          vertexLayout,
          vertexSize: vLen,
          indexSize: iLen,
        };
      } else {
        handle = ctx.meshes.length;
        ctx.meshes.push({
          vertexBuffer,
          indexBuffer,
          indexCount,
          vertexLayout,
          vertexSize: vLen,
          indexSize: iLen,
        });
      }
      return handle;
    },
    webgpu_update_mesh(ctxId, handle, vPtr, vLen, iPtr, iLen) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const mesh = ctx.meshes[handle];
      if (!mesh) return;
      const vertices = new Uint8Array(memory.buffer, vPtr, vLen);
      const indices = new Uint8Array(memory.buffer, iPtr, iLen);
      if (vLen > mesh.vertexSize || iLen > mesh.indexSize) {
        if (mesh.vertexBuffer) mesh.vertexBuffer.destroy();
        if (mesh.indexBuffer) mesh.indexBuffer.destroy();
        webgpuDestroys.buffers += 2;
        mesh.vertexBuffer = createBufferWithData(ctx.device, vertices, GPUBufferUsage.VERTEX);
        mesh.indexBuffer = createBufferWithData(ctx.device, indices, GPUBufferUsage.INDEX);
        mesh.vertexSize = vLen;
        mesh.indexSize = iLen;
      } else {
        ctx.queue.writeBuffer(mesh.vertexBuffer, 0, vertices);
        ctx.queue.writeBuffer(mesh.indexBuffer, 0, indices);
      }
      mesh.indexCount = iLen / 2;
    },
    webgpu_create_shader(ctxId, wgslPtr, wgslLen) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const wgsl = readString(wgslPtr, wgslLen);
      const shader = createColorPipelinesFromWgsl(ctx, wgsl);
      let handle = 0;
      if (ctx.shaderFree.length > 0) {
        handle = ctx.shaderFree.pop();
        ctx.shaders[handle] = shader;
      } else {
        handle = ctx.shaders.length;
        ctx.shaders.push(shader);
      }
      return handle;
    },
    webgpu_create_shader_configured(ctxId, wgslPtr, wgslLen, vertexLayout, bindingMode) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const wgsl = readString(wgslPtr, wgslLen);
      const shader = bindingMode === 0
        ? createColorPipelinesFromWgsl(ctx, wgsl)
        : bindingMode === 1 || bindingMode === 2 || bindingMode === 3
          ? createMaterialPipelinesFromWgsl(ctx, wgsl, vertexLayout, bindingMode)
          : null;
      if (!shader) return 0;
      let handle = 0;
      if (ctx.shaderFree.length > 0) {
        handle = ctx.shaderFree.pop();
        ctx.shaders[handle] = shader;
      } else {
        handle = ctx.shaders.length;
        ctx.shaders.push(shader);
      }
      return handle;
    },
    webgpu_create_shadow_shader_configured(ctxId, wgslPtr, wgslLen, vertexLayout, bindingMode) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const wgsl = readString(wgslPtr, wgslLen);
      const shader = createShadowPipelinesFromWgsl(ctx, wgsl, vertexLayout, bindingMode);
      if (!shader) return 0;
      let handle = 0;
      if (ctx.shaderFree.length > 0) {
        handle = ctx.shaderFree.pop();
        ctx.shaders[handle] = shader;
      } else {
        handle = ctx.shaders.length;
        ctx.shaders.push(shader);
      }
      return handle;
    },
    webgpu_create_post_process_shader(ctxId, wgslPtr, wgslLen) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const wgsl = readString(wgslPtr, wgslLen);
      const shader = createPostProcessPipelinesFromWgsl(ctx, wgsl);
      let handle = 0;
      if (ctx.postProcessShaderFree.length > 0) {
        handle = ctx.postProcessShaderFree.pop();
        ctx.postProcessShaders[handle] = shader;
      } else {
        handle = ctx.postProcessShaders.length;
        ctx.postProcessShaders.push(shader);
      }
      return handle;
    },
    webgpu_destroy_shader(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const shader = ctx.shaders[handle];
      if (!shader) return;
      ctx.shaders[handle] = null;
      webgpuDestroys.pipelines += 2;
      if (handle !== 0) {
        ctx.shaderFree.push(handle);
      }
    },
    webgpu_destroy_shadow_shader(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const shader = ctx.shaders[handle];
      if (!shader) return;
      ctx.shaders[handle] = null;
      webgpuDestroys.pipelines += 1;
      if (handle !== 0) {
        ctx.shaderFree.push(handle);
      }
    },
    webgpu_destroy_post_process_shader(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const shader = ctx.postProcessShaders[handle];
      if (!shader) return;
      ctx.postProcessShaders[handle] = null;
      webgpuDestroys.pipelines += 2;
      if (handle !== 0) {
        ctx.postProcessShaderFree.push(handle);
      }
    },
    webgpu_destroy_mesh(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const mesh = ctx.meshes[handle];
      if (mesh) {
        if (mesh.vertexBuffer) mesh.vertexBuffer.destroy();
        if (mesh.indexBuffer) mesh.indexBuffer.destroy();
        webgpuDestroys.buffers += 2;
      }
      ctx.meshes[handle] = null;
      if (handle !== 0) {
        ctx.meshFree.push(handle);
      }
    },
    webgpu_ensure_shadow_map_slot(ctxId, slotIndex, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      ensureShadowMapSlot(ctx, slotIndex >>> 0, width, height);
      return slotIndex >>> 0;
    },
    webgpu_resource_counts(outCreatesPtr, outDestroysPtr) {
      const view = getMemoryView();
      const createBase = outCreatesPtr;
      view.setUint32(createBase + 0, webgpuCreates.buffers, true);
      view.setUint32(createBase + 4, webgpuCreates.textures, true);
      view.setUint32(createBase + 8, webgpuCreates.textureViews, true);
      view.setUint32(createBase + 12, webgpuCreates.samplers, true);
      view.setUint32(createBase + 16, webgpuCreates.bindGroups, true);
      view.setUint32(createBase + 20, webgpuCreates.pipelines, true);
      view.setUint32(createBase + 24, webgpuCreates.commandEncoders, true);
      view.setUint32(createBase + 28, webgpuCreates.renderPasses, true);
      view.setUint32(createBase + 32, webgpuFramesBegun, true);
      view.setUint32(createBase + 36, webgpuFramesEnded, true);
      view.setUint32(createBase + 40, gpuFramesInFlight, true);
      view.setUint32(createBase + 44, Math.floor(lastQueueWaitMs), true);
      view.setUint32(createBase + 48, Math.floor(maxQueueWaitMs), true);

      const destroyBase = outDestroysPtr;
      view.setUint32(destroyBase + 0, webgpuDestroys.buffers, true);
      view.setUint32(destroyBase + 4, webgpuDestroys.textures, true);
      view.setUint32(destroyBase + 8, webgpuDestroys.samplers, true);
      view.setUint32(destroyBase + 12, webgpuDestroys.bindGroups, true);
      view.setUint32(destroyBase + 16, webgpuDestroys.pipelines, true);
    },
    webgpu_stats(ctxId, outPtr) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      const view = getMemoryView();
      const stats = collectWebGpuStats(ctx);
      view.setUint32(outPtr + 0, stats.meshesAlive, true);
      view.setUint32(outPtr + 4, stats.meshesSlots, true);
      view.setUint32(outPtr + 8, stats.meshesFree, true);
      view.setUint32(outPtr + 12, stats.texturesAlive, true);
      view.setUint32(outPtr + 16, stats.texturesSlots, true);
      view.setUint32(outPtr + 20, stats.materialsAlive, true);
      view.setUint32(outPtr + 24, stats.materialsSlots, true);
      view.setUint32(outPtr + 28, stats.samplersAlive, true);
      view.setUint32(outPtr + 32, stats.samplersSlots, true);
    },
    webgpu_error_counts(outValidationPtr, outOutOfMemoryPtr, outInternalPtr) {
      const view = getMemoryView();
      view.setUint32(outValidationPtr, webgpuErrors.validation, true);
      view.setUint32(outOutOfMemoryPtr, webgpuErrors.outOfMemory, true);
      view.setUint32(outInternalPtr, webgpuErrors.internal, true);
    },
    webgpu_device_lost(outPtr) {
      const view = getMemoryView();
      view.setUint32(outPtr, deviceLost ? 1 : 0, true);
    },
    wasm_time_ms() {
      return performance.now();
    },
    wasmAudioLoad(ptr, len) {
      const ctx = ensureAudioContext();
      if (!ctx) return 0;
      const bytes = new Uint8Array(memory.buffer, ptr, len);
      const copy = bytes.slice();
      const id = nextSoundId++;
      const entry = { buffer: null };
      soundBuffers.set(id, entry);
      ctx.decodeAudioData(copy.buffer.slice(0)).then((buffer) => {
        entry.buffer = buffer;
      }).catch(() => {});
      return id;
    },
    wasmAudioUnload(id) {
      soundBuffers.delete(id);
    },
    wasmAudioPlay(id, volume, loop) {
      const ctx = ensureAudioContext();
      if (!ctx) return 0;
      const entry = soundBuffers.get(id);
      if (!entry || !entry.buffer) return 0;
      const source = ctx.createBufferSource();
      source.buffer = entry.buffer;
      source.loop = Boolean(loop);
      const gain = ctx.createGain();
      gain.gain.value = volume;
      source.connect(gain).connect(ctx.destination);
      const handle = nextSoundHandle++;
      activeSounds.set(handle, { source, gain });
      source.onended = () => {
        activeSounds.delete(handle);
      };
      source.start(0);
      return handle;
    },
    wasmAudioIsPlaying(handle) {
      return activeSounds.has(handle) ? 1 : 0;
    },
  },
};

async function start() {
  if (!navigator.gpu) {
    document.querySelector(".hint").textContent = "WebGPU: unavailable";
    return;
  }
  try {
    await initDevice();
    await loadShaders();
  } catch (err) {
    document.querySelector(".hint").textContent = "WebGPU: adapter unavailable";
    console.error("[phasor] webgpu init failed", err);
    return;
  }

  const response = await fetch(wasmUrl);
  if (!response.ok) {
    throw new Error(`Failed to fetch wasm: ${response.status}`);
  }
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, imports);
  wasm = result.instance;
  memory = wasm.exports.memory;

  try {
    await joltEnv.init();
  } catch (err) {
    document.querySelector(".hint").textContent = "WebGPU: Jolt init failed";
    console.error("[phasor] jolt init failed", err);
    return;
  }

  if (phasorDebug.lifecycleLogs) {
    console.log("[phasor] exports", Object.keys(wasm.exports));
  }

  if (wasm.exports.wasmCreate) {
    try {
      wasmApp = wasm.exports.wasmCreate();
      if (phasorDebug.lifecycleLogs) {
        console.log("[phasor] wasmCreate returned", wasmApp);
      }
    } catch (err) {
      console.error("[phasor] wasmCreate threw", err);
      wasmApp = 0;
    }
    if (!wasmApp) {
      let reason = "unknown";
      if (wasm.exports.wasmLastErrorPtr && wasm.exports.wasmLastErrorLen) {
        const ptr = wasm.exports.wasmLastErrorPtr();
        const len = wasm.exports.wasmLastErrorLen();
        if (ptr && len) {
          reason = readString(ptr, len);
        }
      }
      console.error("[phasor] wasmCreate failed", reason);
      const hint = document.querySelector(".hint");
      if (hint) hint.textContent = `WebGPU: wasmCreate failed (${reason})`;
    }
  }

  if (wasm.exports.wasmWindowTitlePtr && wasm.exports.wasmWindowTitleLen) {
    const ptr = wasm.exports.wasmWindowTitlePtr();
    const len = wasm.exports.wasmWindowTitleLen();
    if (ptr && len) {
      setPageTitle(readString(ptr, len));
    }
  }

  useVsync = true;
  if (wasm.exports.wasmVsyncEnabled) {
    useVsync = Boolean(wasm.exports.wasmVsyncEnabled());
  }

  let useFullscreen = false;
  if (wasm.exports.wasmFullscreenEnabled) {
    useFullscreen = Boolean(wasm.exports.wasmFullscreenEnabled());
  }
  pauseOnGpuError = false;
  if (wasm.exports.wasmPauseOnGpuErrorEnabled) {
    pauseOnGpuError = Boolean(wasm.exports.wasmPauseOnGpuErrorEnabled());
  }
  if (useFullscreen) {
    document.documentElement.classList.add("fullscreen");
    document.body.classList.add("fullscreen");
  }

function handleKeyEvent(isDown, event) {
    if (!wasm.exports.wasmInputKey) return;
    ensureAudioContext();
    const key = mapKeyboardEvent(event);
    if (key == null) return;
    wasm.exports.wasmInputKey(key, isDown ? 1 : 0);
    event.preventDefault();
  }

  function updatePointerState(event) {
    const canvas = document.querySelector("#canvas");
    if (!canvas || !wasm || !wasm.exports) return canvas;

    if (wasm.exports.wasmInputMousePosition) {
      const rect = canvas.getBoundingClientRect();
      const x = event.clientX - rect.left;
      const y = event.clientY - rect.top;
      wasm.exports.wasmInputMousePosition(x, y);
    }
    return canvas;
  }

  window.addEventListener("keydown", (event) => handleKeyEvent(true, event));
  window.addEventListener("keyup", (event) => handleKeyEvent(false, event));
  window.addEventListener("pointerdown", (event) => {
    ensureAudioContext();
    const canvas = updatePointerState(event);
    if (!canvas) return;
    if (wasm && wasm.exports && wasm.exports.wasmInputMouseButton) {
      wasm.exports.wasmInputMouseButton(event.button, 1);
    }
    if (wantsMouseCapture && document.pointerLockElement !== canvas && canvas.requestPointerLock) {
      canvas.requestPointerLock().catch(() => {});
    }
  });
  window.addEventListener("pointerup", (event) => {
    updatePointerState(event);
    if (!wasm || !wasm.exports || !wasm.exports.wasmInputMouseButton) return;
    wasm.exports.wasmInputMouseButton(event.button, 0);
  });
  window.addEventListener("mousemove", (event) => {
    const canvas = updatePointerState(event);
    if (!canvas) return;
    if (!wasm || !wasm.exports || !wasm.exports.wasmInputMouseDelta) return;
    if (!wantsMouseCapture) return;
    if (document.pointerLockElement !== canvas) return;
    wasm.exports.wasmInputMouseDelta(event.movementX, event.movementY);
  });

  function resizeAndNotify() {
    const canvas = document.querySelector("#canvas");
    const size = resizeCanvas(canvas);
    if (wasm.exports.wasmResize) {
      wasm.exports.wasmResize(
        wasmApp,
        size.logicalWidth,
        size.logicalHeight,
        size.framebufferWidth,
        size.framebufferHeight,
      );
    }
  }

  function resumeFromBackground(reason) {
    if (document.visibilityState && document.visibilityState !== "visible") return;
    ensureAudioContext();
    resizeAndNotify();
    for (const ctx of ctxs.values()) {
      reconfigureContextSurface(ctx, reason);
    }
    if (resumeFrameLoop) {
      resumeFrameLoop();
    }
  }

  window.addEventListener("resize", resizeAndNotify);
  window.addEventListener("focus", () => resumeFromBackground("focus"));
  window.addEventListener("pageshow", () => resumeFromBackground("pageshow"));
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      resumeFromBackground("visibilitychange");
    }
  });
  resizeAndNotify();

  function frame() {
    lastFrameStartedAtMs = performance.now();
    try {
      if (!simulationPaused && shouldPauseSimulation()) {
        simulationPaused = true;
        console.error("[phasor] simulation paused due to WebGPU failure");
        const hint = document.querySelector(".hint");
        if (hint) hint.textContent = "WebGPU: paused (device lost or GPU error)";
        if (shouldRecoverSimulation()) {
          recoverWebGpu().catch((err) => {
            console.error("[phasor] webgpu recovery failed", err);
          });
        }
        scheduleNextFrame(frame);
        return;
      }
      if (simulationPaused) {
        if (shouldRecoverSimulation()) {
          recoverWebGpu().catch((err) => {
            console.error("[phasor] webgpu recovery failed", err);
          });
        }
        scheduleNextFrame(frame);
        return;
      }
      if (gpuFramesInFlight >= maxFramesInFlight) {
        scheduleNextFrame(frame);
        return;
      }
      if (wasm.exports.wasmFrame) {
        if (phasorDebug.frameWatchdog) {
          frameTimeoutId = setTimeout(() => {
            console.warn("[phasor] wasmFrame stall > 1s", "frame=" + frameIndex);
          }, 1000);
        }
        wasm.exports.wasmFrame(wasmApp);
        reportWasmError(captureLastWasmError());
        if (frameTimeoutId != null) {
          clearTimeout(frameTimeoutId);
          frameTimeoutId = null;
        }
        lastFrameFinishedAtMs = performance.now();
      }
    } catch (err) {
      console.error("[phasor] wasmFrame error:", err);
      const hint = document.querySelector(".hint");
      if (hint) hint.textContent = "WebGPU: wasmFrame error (see console)";
      scheduleNextFrame(frame);
      return;
    }
    scheduleNextFrame(frame);
  }
  resumeFrameLoop = () => {
    scheduleNextFrame(frame);
  };
  resumeFrameLoop();

  if (phasorDebug.frameWatchdog && frameWatchdogIntervalId == null) {
    frameWatchdogIntervalId = setInterval(() => {
      if (document.visibilityState && document.visibilityState !== "visible") return;
      if (!wasm || !wasm.exports || !wasmApp) return;
      if (recoveringDevice) return;

      const now = performance.now();
      const lastActive = Math.max(lastFrameFinishedAtMs, lastFrameStartedAtMs, lastFrameScheduledAtMs);
      if (lastActive <= 0) return;
      const stalledMs = now - lastActive;
      if (stalledMs < 4000) return;
      if ((now - lastWatchdogKickAtMs) < 1500) return;
      lastWatchdogKickAtMs = now;

      const hint = document.querySelector(".hint");
      if (hint) {
        hint.textContent = "WebGPU: frame stall detected, attempting resume";
      }
      resumeFromBackground("watchdog_stall");
    }, 1000);
  }

  window.addEventListener("beforeunload", () => {
    if (frameWatchdogIntervalId != null) {
      clearInterval(frameWatchdogIntervalId);
      frameWatchdogIntervalId = null;
    }
    if (wasm.exports.wasmDeinit && wasmApp) {
      wasm.exports.wasmDeinit(wasmApp);
      wasmApp = 0;
    }
  });
}

start().catch((err) => {
  console.error("[phasor] start failed:", err);
  const hint = document.querySelector(".hint");
  if (hint) hint.textContent = "WebGPU: start failed (see console)";
});
