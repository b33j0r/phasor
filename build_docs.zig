const std = @import("std");

pub fn addDocsSiteSteps(b: *std.Build) void {
    const docs_validate = b.addSystemCommand(&.{
        "uv",
        "run",
        "phasor-docs-site",
        "validate",
    });
    docs_validate.setCwd(b.path("."));
    const docs_validate_step = b.step("docs-validate", "Validate docs manifests, embeds, and example discovery");
    docs_validate_step.dependOn(&docs_validate.step);

    const docs_generate = b.addSystemCommand(&.{
        "uv",
        "run",
        "phasor-docs-site",
        "generate",
    });
    docs_generate.setCwd(b.path("."));

    const docs_step = b.step("docs", "Generate the docs site");
    docs_step.dependOn(&docs_generate.step);

    const docs_site_step = b.step("docs-site", "Generate the docs site");
    docs_site_step.dependOn(&docs_generate.step);

    const docs_serve = b.addSystemCommand(&.{
        "uv",
        "run",
        "phasor-docs-site",
        "serve",
        "--host",
        "127.0.0.1",
        "--port",
        "8011",
    });
    docs_serve.setCwd(b.path("."));
    if (b.args) |args| {
        docs_serve.addArgs(args);
    }

    const run_docs_step = b.step("run-docs", "Generate and serve the docs site preview");
    run_docs_step.dependOn(&docs_serve.step);

    const docs_serve_step = b.step("docs-serve", "Generate and serve the docs site preview");
    docs_serve_step.dependOn(&docs_serve.step);
}
