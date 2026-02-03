console.log("[phasor] webgpu.js loaded");

const wasmUrl = new URL("app.wasm", import.meta.url);
const triangleShaderUrl = new URL("shaders/triangle.wgsl", import.meta.url);
const quadShaderUrl = new URL("shaders/quad.wgsl", import.meta.url);

const ctxs = new Map();
let nextCtxId = 1;
let wasm = null;
let memory = null;
let device = null;
let wasmApp = 0;
let shaderSources = null;
let audioCtx = null;
const soundBuffers = new Map();
const activeSounds = new Map();
let nextSoundId = 1;
let nextSoundHandle = 1;

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

function resizeCanvas(canvas) {
  const scale = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  const width = Math.max(1, Math.floor(rect.width * scale));
  const height = Math.max(1, Math.floor(rect.height * scale));
  if (canvas.width !== width || canvas.height !== height) {
    canvas.width = width;
    canvas.height = height;
  }
  return { width, height };
}

function createBufferWithData(device, data, usage) {
  const buffer = device.createBuffer({
    size: data.byteLength,
    usage,
    mappedAtCreation: true,
  });
  new Uint8Array(buffer.getMappedRange()).set(new Uint8Array(data.buffer, data.byteOffset, data.byteLength));
  buffer.unmap();
  return buffer;
}

function createDepthTexture(ctx, width, height) {
  if (ctx.depthTexture) {
    ctx.depthTexture.destroy();
  }
  ctx.depthTexture = ctx.device.createTexture({
    size: { width, height },
    format: "depth24plus",
    usage: GPUTextureUsage.RENDER_ATTACHMENT,
  });
  ctx.depthView = ctx.depthTexture.createView();
}

async function loadShaders() {
  if (shaderSources) return shaderSources;
  const [triangleShader, quadShader] = await Promise.all([
    fetch(triangleShaderUrl).then((resp) => resp.text()),
    fetch(quadShaderUrl).then((resp) => resp.text()),
  ]);
  shaderSources = { triangleShader, quadShader };
  return shaderSources;
}

function createPipelines(ctx) {
  if (!shaderSources) {
    throw new Error("Shaders not loaded");
  }
  const triangleShader = shaderSources.triangleShader;
  const quadShader = shaderSources.quadShader;
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
          arrayStride: 80,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
            { shaderLocation: 6, offset: 64, format: "float32x4" },
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
          arrayStride: 80,
          stepMode: "instance",
          attributes: [
            { shaderLocation: 2, offset: 0, format: "float32x4" },
            { shaderLocation: 3, offset: 16, format: "float32x4" },
            { shaderLocation: 4, offset: 32, format: "float32x4" },
            { shaderLocation: 5, offset: 48, format: "float32x4" },
            { shaderLocation: 6, offset: 64, format: "float32x4" },
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
}

function createContext(canvas) {
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
    textures: [null],
    samplers: [null],
    materials: [null],
    instanceBufferSize: 256 * 1024,
    instanceOffset: 0,
    depthTexture: null,
    depthView: null,
  };

  createPipelines(ctx);
  createDepthTexture(ctx, size.width, size.height);

  ctx.instanceBuffer = device.createBuffer({
    size: ctx.instanceBufferSize,
    usage: GPUBufferUsage.VERTEX | GPUBufferUsage.COPY_DST,
  });

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
    webgpu_canvas_size(canvasPtr, canvasLen, outW, outH) {
      const id = readString(canvasPtr, canvasLen);
      const canvas = document.querySelector(id);
      const size = resizeCanvas(canvas);
      const view = getMemoryView();
      view.setUint32(outW, size.width, true);
      view.setUint32(outH, size.height, true);
    },
    webgpu_init(canvasPtr, canvasLen, _enableValidation) {
      const id = readString(canvasPtr, canvasLen);
      const canvas = document.querySelector(id);
      if (!canvas) {
        return 0;
      }
      const ctx = createContext(canvas);
      const ctxId = nextCtxId++;
      ctxs.set(ctxId, ctx);
      return ctxId;
    },
    webgpu_deinit(ctxId) {
      ctxs.delete(ctxId);
    },
    webgpu_resize(ctxId, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.canvas.width = width;
      ctx.canvas.height = height;
      ctx.context.configure({
        device: ctx.device,
        format: ctx.format,
        alphaMode: "premultiplied",
      });
      createDepthTexture(ctx, width, height);
    },
    webgpu_begin_frame(ctxId, r, g, b, a) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.instanceOffset = 0;
      const encoder = ctx.device.createCommandEncoder();
      const view = ctx.context.getCurrentTexture().createView();
      const pass = encoder.beginRenderPass({
        colorAttachments: [{
          view,
          loadOp: "clear",
          storeOp: "store",
          clearValue: { r, g, b, a },
        }],
        depthStencilAttachment: {
          view: ctx.depthView,
          depthLoadOp: "clear",
          depthStoreOp: "store",
          depthClearValue: 1.0,
        },
      });
      ctx.encoder = encoder;
      ctx.pass = pass;
    },
    webgpu_draw_triangle(ctxId) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.pass.setPipeline(ctx.trianglePipeline);
      ctx.pass.setVertexBuffer(0, ctx.triangleVertexBuffer);
      ctx.pass.draw(3, 1, 0, 0);
    },
    webgpu_draw_textured_quad(ctxId, meshHandle, materialHandle, instancePtr, blend) {
      const ctx = ctxs.get(ctxId);
      const mesh = ctx.meshes[meshHandle];
      const material = ctx.materials[materialHandle];
      if (!ctx || !mesh || !material) return;
      const instanceData = new Float32Array(memory.buffer, instancePtr, 20);
      const stride = 80;
      const alignment = 256;
      let offset = Math.ceil(ctx.instanceOffset / alignment) * alignment;
      if (offset + stride > ctx.instanceBufferSize) {
        offset = 0;
      }
      ctx.instanceOffset = offset + stride;
      ctx.queue.writeBuffer(ctx.instanceBuffer, offset, instanceData);

      const pipeline = blend ? ctx.quadPipelineBlend : ctx.quadPipelineOpaque;
      ctx.pass.setPipeline(pipeline);
      ctx.pass.setBindGroup(0, material.bindGroup);
      ctx.pass.setVertexBuffer(0, mesh.vertexBuffer);
      ctx.pass.setVertexBuffer(1, ctx.instanceBuffer, offset, stride);
      ctx.pass.setIndexBuffer(mesh.indexBuffer, "uint16");
      ctx.pass.drawIndexed(mesh.indexCount, 1, 0, 0, 0);
    },
    webgpu_end_frame(ctxId) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.pass.end();
      ctx.queue.submit([ctx.encoder.finish()]);
      ctx.pass = null;
      ctx.encoder = null;
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
      const handle = ctx.samplers.length;
      ctx.samplers.push(sampler);
      return handle;
    },
    webgpu_destroy_sampler(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.samplers[handle] = null;
    },
    webgpu_create_texture_rgba8(ctxId, _samplerHandle, dataPtr, dataLen, width, height) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const texture = ctx.device.createTexture({
        size: { width, height },
        format: "rgba8unorm",
        usage: GPUTextureUsage.TEXTURE_BINDING | GPUTextureUsage.COPY_DST,
      });
      const view = texture.createView();
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
    webgpu_destroy_texture(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
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
      const handle = ctx.materials.length;
      ctx.materials.push({ bindGroup });
      return handle;
    },
    webgpu_destroy_material(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.materials[handle] = null;
    },
    webgpu_create_mesh(ctxId, vPtr, vLen, iPtr, iLen) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return 0;
      const vertices = new Uint8Array(memory.buffer, vPtr, vLen);
      const indices = new Uint8Array(memory.buffer, iPtr, iLen);
      const vertexBuffer = createBufferWithData(ctx.device, vertices, GPUBufferUsage.VERTEX);
      const indexBuffer = createBufferWithData(ctx.device, indices, GPUBufferUsage.INDEX);
      const indexCount = iLen / 2;
      const handle = ctx.meshes.length;
      ctx.meshes.push({ vertexBuffer, indexBuffer, indexCount });
      return handle;
    },
    webgpu_destroy_mesh(ctxId, handle) {
      const ctx = ctxs.get(ctxId);
      if (!ctx) return;
      ctx.meshes[handle] = null;
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
  const adapter = await navigator.gpu.requestAdapter();
  if (!adapter) {
    document.querySelector(".hint").textContent = "WebGPU: adapter unavailable";
    return;
  }
  device = await adapter.requestDevice();
  await loadShaders();

  const response = await fetch(wasmUrl);
  if (!response.ok) {
    throw new Error(`Failed to fetch wasm: ${response.status}`);
  }
  const bytes = await response.arrayBuffer();
  const result = await WebAssembly.instantiate(bytes, imports);
  wasm = result.instance;
  memory = wasm.exports.memory;

  console.log("[phasor] exports", Object.keys(wasm.exports));

  if (wasm.exports.wasmCreate) {
    wasmApp = wasm.exports.wasmCreate();
    console.log("[phasor] wasmCreate returned", wasmApp);
    if (!wasmApp) {
      let reason = "unknown";
      if (wasm.exports.wasmLastErrorPtr && wasm.exports.wasmLastErrorLen) {
        const ptr = wasm.exports.wasmLastErrorPtr();
        const len = wasm.exports.wasmLastErrorLen();
        if (ptr && len) {
          reason = readString(ptr, len);
        }
      }
      const hint = document.querySelector(".hint");
      if (hint) hint.textContent = `WebGPU: wasmCreate failed (${reason})`;
    }
  }

  let useVsync = true;
  if (wasm.exports.wasmVsyncEnabled) {
    useVsync = Boolean(wasm.exports.wasmVsyncEnabled());
  }

  let useFullscreen = false;
  if (wasm.exports.wasmFullscreenEnabled) {
    useFullscreen = Boolean(wasm.exports.wasmFullscreenEnabled());
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

  window.addEventListener("keydown", (event) => handleKeyEvent(true, event));
  window.addEventListener("keyup", (event) => handleKeyEvent(false, event));
  window.addEventListener("pointerdown", () => ensureAudioContext());

  function resizeAndNotify() {
    const canvas = document.querySelector("#canvas");
    const size = resizeCanvas(canvas);
    if (wasm.exports.wasmResize) {
      wasm.exports.wasmResize(size.width, size.height);
    }
  }
  window.addEventListener("resize", resizeAndNotify);
  resizeAndNotify();

  function frame() {
    try {
      if (wasm.exports.wasmFrame) {
        wasm.exports.wasmFrame(wasmApp);
      }
    } catch (err) {
      console.error("[phasor] wasmFrame error:", err);
      const hint = document.querySelector(".hint");
      if (hint) hint.textContent = "WebGPU: wasmFrame error (see console)";
      return;
    }
    if (useVsync) {
      requestAnimationFrame(frame);
    } else {
      setTimeout(frame, 0);
    }
  }
  if (useVsync) {
    requestAnimationFrame(frame);
  } else {
    setTimeout(frame, 0);
  }

  window.addEventListener("beforeunload", () => {
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
