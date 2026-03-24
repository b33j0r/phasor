# Branch Resume: `normals`

This branch is intentionally being put on ice. Read this file after `/Users/brian/Projects/phasor/AGENTS.md` and `/Users/brian/Projects/phasor/local/CONTEXT.md` before changing code.

## Goal

Debug the Sponza curtain/banner rendering regression without adding Sponza-only hacks. The long-term direction is to fix renderer/shader correctness and keep example customization moving toward inversion of control.

## Current Branch State

- Branch: `normals`
- Repo: `/Users/brian/Projects/phasor/phasor-lite`
- Rebased onto local `main` on 2026-03-23.
- Rebase follow-up:
  - kept the `main` phase-owned Sponza system wiring
  - re-added normals-only `V` / `B` inputs in `examples/sponza/phases.zig`
  - removed duplicated top-level `app.addSystemTo(...)` wiring from `examples/sponza/main.zig`
- Interactive smoke check most recently passed with:
  - `timeout 15s /Users/brian/src/zig/build/stage3/bin/zig build run-sponza`
- Latest successful smoke behavior:
  - app reached `app startup complete`
  - app stayed up until `timeout` after the rebase fix
  - new `B` toggle for environment specular still exists for live comparison

## Strongest Current Conclusion

The bad banner/curtain look is not primarily caused by:
- glTF metallic/roughness decoding
- normal-strength scaling alone
- high-level lighting on/off
- shadows

Normal maps are now actually wired through the renderer on this branch:
- glTF `normal_texture` / `normal_scale` were already parsed
- scene materials now bind a normal texture
- the Sponza PBR shader now applies tangent-space normals using glTF-authored mesh tangents
- Sponza now uploads a dedicated `position/normal/tangent/uv` mesh layout instead of reconstructing tangent space from screen-space derivatives

The main remaining problem is the environment specular approximation in the Sponza PBR shader.

User confirmed:
- metallic debug view looks correct
- roughness debug view looks correct
- normal debug view looks correct enough to not be the primary failure
- pressing `B` to disable environment specular removes the specular overload

That means the dominant-direction environment specular proxy is the current culprit.

## What Was Tried

### Failed / Dead Ends

- Suspected normal map strength / glTF normal scale issue.
  - Curtains looked somewhat plausible, ornaments looked terrible.
  - Turning normals off made little visible difference.
- Suspected lighting/day-night bug.
  - Lighting-off tests still looked bad.
- Suspected sky-mode issue.
  - Procedural-vs-HDRI comparison was started, then canceled after lighting-off also failed to explain the bug.
- Suspected shadows.
  - On this branch, Sponza was already effectively not rendering directional shadows.
  - A generic `render.ShadowMode` resource was still added, but this did not explain the artifact.
- Suspected metallic/roughness import bug.
  - Debug views and shader review did not support this as the primary cause.

### Successful Investigations

- Added renderer-owned debug views for:
  - base color
  - normal
  - metallic
  - roughness
  - AO
  - NdotL
  - NdotV
  - specular only
- Added a renderer-owned environment specular toggle.
  - `B` toggles environment specular on/off in Sponza.
  - User confirmed `B` fixes the specular overload.
- Corrected one real IBL energy issue:
  - diffuse environment lighting now uses Fresnel-aware energy split instead of always using full `(1 - metallic)` diffuse.
- Replaced the sharp dominant-direction environment proxy with a softer fallback:
  - rough materials now lean more on low-frequency irradiance sampled along the reflection vector
  - smoother materials still get a dominant-direction lobe, but with much lower energy and a softer exponent
  - this keeps the investigation renderer-level without adding Sponza material hacks
- Implemented actual normal-map consumption in the renderer:
  - scene materials now carry a bound normal texture with a flat-normal fallback
  - `scene_pbr_lit.wgsl` samples the normal map and applies `normal_scale`
  - tangent space now comes from glTF `TANGENT` data threaded through the importer, native/web mesh layouts, and shadow pipeline variants

## User Findings To Preserve

- Sponza loads beautifully in Blender, so the solution should not be Sponza-specific material hacks.
- The banner logos may not actually be raised in the normal map; they may be screenprinted.
- Metallic and roughness views looked believable.
- Normal view looked believable enough that tangent-space import is not the first thing to blame now.
- Environment specular toggle (`B`) clearly reduces or removes the bad overloaded sheen.

## Code Changes Already On This Branch

### Generic Renderer Resources

- `/Users/brian/Projects/phasor/phasor-lite/lib/render/root.zig`
  - `render.ShadowMode`
  - `render.SceneDebugView`
  - `render.EnvironmentSpecularMode`

- `/Users/brian/Projects/phasor/phasor-lite/lib/modules/RenderModule.zig`
  - installs default resources for those renderer controls

- `/Users/brian/Projects/phasor/phasor-lite/lib/modules/render/submit.zig`
  - resolves resource values each frame
  - writes scene debug and environment flags into scene uniforms

- `/Users/brian/Projects/phasor/phasor-lite/lib/render/scene_uniforms.zig`
  - added `debug_view`
  - added `environment_flags`

### Shader Work

- `/Users/brian/Projects/phasor/phasor-lite/examples/sponza/shaders/scene_pbr_lit.wgsl`
  - debug views added
  - diffuse IBL energy split corrected:
    - `kd_ibl = (1 - F_ibl) * (1 - metallic)`
  - environment specular now respects an on/off flag for diagnosis

### Sponza Example Wiring

- `/Users/brian/Projects/phasor/phasor-lite/examples/sponza/gameplay.zig`
  - `V` cycles debug views
  - `B` toggles environment specular
  - HUD exposes current debug/environment-specular state

- `/Users/brian/Projects/phasor/phasor-lite/examples/sponza/main.zig`
  - inserts default resources
  - adds update systems and HUD lines

### Other Branch-Local Changes

- `/Users/brian/Projects/phasor/phasor-lite/examples/sponza/lighting.zig`
  - soft white point light re-established at origin
  - HDRI/panorama set as default startup sky

- `/Users/brian/Projects/phasor/phasor-lite/lib/metrics/root.zig`
  - bus cap increased from `16` to `32` to support added HUD/debug metrics

## Important Current Diagnosis

The direct-light BRDF is not obviously the broken part. The more suspicious shader term is:

- environment specular at `/Users/brian/Projects/phasor/phasor-lite/examples/sponza/shaders/scene_pbr_lit.wgsl`

Current implementation still uses:
- a single dominant environment direction
- a single dominant environment color
- a conservative hybrid fallback instead of real prefiltered environment sampling

This is safer than the earlier sharp proxy, but still not physically robust enough to stand in for proper prefiltered environment sampling.

## Recommended Next Steps

Resume with this order:

1. Keep the Fresnel-aware diffuse IBL split.
2. Compare the curtain/ornament viewpoint again now that normal maps are actually active.
3. Evaluate the softer hybrid fallback against the `B` toggle from the same curtain/ornament viewpoints.
4. Prefer a renderer-level solution over Sponza material overrides.

## Suggested Next Technical Options

### Option A: Safe Default

- Make environment specular default to `off` on this branch.
- Keep the `B` toggle for comparison.
- Treat this as a temporary stabilization path until better IBL exists.

### Option B: Better Fallback

- Keep environment specular enabled, but replace the current dominant-direction `pow(...)` lobe with something much softer and lower-energy.
- Goal: preserve a hint of image-based gloss without chrome-like cloth artifacts.

### Option C: Proper Fix

- Add real prefiltered environment specular support.
- This is the correct long-term path, but larger scope.

## Branch History Worth Remembering

- There was an earlier branch `normals-and-automation-prototype-1`.
- That branch contained broader automation/config work and screenshot control experiments.
- This `normals` branch intentionally stayed simpler and more focused on the rendering bug.

## Controls On This Branch

- `V`: cycle debug material views
- `B`: toggle environment specular on/off
- `C`: cycle color grading
- `H`: toggle sky mode
- `P`: manual screenshot
- `O`: auto screenshot

## Resume Command

Use:

```bash
cd /Users/brian/Projects/phasor/phasor-lite
timeout 15s /Users/brian/src/zig/build/stage3/bin/zig build run-sponza
```

For manual comparison, run without `timeout`:

```bash
cd /Users/brian/Projects/phasor/phasor-lite
/Users/brian/src/zig/build/stage3/bin/zig build run-sponza
```
