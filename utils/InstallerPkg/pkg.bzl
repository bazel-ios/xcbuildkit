def _pkg_impl(ctx):
    # Use the name of the app
    # This relies on the convention of macos_application
    app_name = ctx.attr.app.label.name
    extracted_app = ctx.actions.declare_directory(app_name + "_app_dir")

    # Bazel givs us the .app as a zip file.
    # Unzip so we can directly package the .app
    unzip_cmd = [
        "mkdir -p " + extracted_app.path + ";",
        "unzip", 
        "-q", 
        ctx.expand_location("$(location " + str(ctx.attr.app.label) + ")", targets=[ctx.attr.app]),
        "-d",
        extracted_app.path,
    ]
    ctx.actions.run_shell(inputs=ctx.attr.app.files, outputs=[extracted_app],
        command=" ".join(unzip_cmd))

    cmd = [
        "pkgbuild", 
        "--root",
        # This puts the .app at the root of the package
        # And causes the install_location to be the name of the app.
        # e.g. /opt/XCBuildKit/XCBuildKit.app
        extracted_app.path + "/" + app_name + ".app",
        "--identifier",
        ctx.attr.identifier,
        "--version",
        ctx.attr.version,

        "--install-location", ctx.attr.install_location,
        ctx.outputs.pkg.path
    ]

    inputs = [extracted_app]
    if ctx.attr.scripts:
        scripts = ctx.attr.scripts.files.to_list()
        inputs.extend(scripts)
        cmd.extend(["--scripts", scripts[0].dirname])

    ctx.actions.run_shell(outputs=[ctx.outputs.pkg], command=" ".join(cmd),
        inputs=inputs)

# Consider implementing this into rules apple or more generally
# https://github.com/bazelbuild/rules_pkg/tree/master/pkg
# Provide a similar API as pkgbuild, but glob the "scripts" attribute
macos_application_installer_pkg = rule(
    implementation = _pkg_impl,
    attrs = {
        "app" : attr.label(),
        "identifier": attr.string(),
        "version": attr.string(default="1.0"),
        "install_location": attr.string(),
        "scripts": attr.label(),
    },
    outputs = { "pkg": "%{name}.pkg" }
)

def _product_impl(ctx):
    # Use the name of the app
    # This relies on the convention of macos_application
    input_pkg = ctx.attr.package.files.to_list()[0]
    distribution = ctx.attr.distribution.files.to_list()[0]
    cmd = [
        "productbuild", 
        "--distribution",
        distribution.path,
        "--version",
        ctx.attr.version,
        "--package-path",
        input_pkg.dirname,
        ctx.outputs.pkg.path
    ]
    inputs = [distribution, input_pkg]
    if ctx.attr.resources:
        resources = ctx.attr.resources.files.to_list()
        inputs.extend(resources)
        cmd.extend(["--resources", resources[0].dirname])

    print("Inputs", inputs)
    ctx.actions.run_shell(outputs=[ctx.outputs.pkg], command=" ".join(cmd),
        inputs=inputs)

# Builds packagebuild product
macos_application_installer_product = rule(
    implementation = _product_impl,
    attrs = {
        "distribution" : attr.label(allow_single_file=True),
        "resources": attr.label(allow_single_file=True),
        "version": attr.string(),
        "package": attr.label(allow_single_file=True),
    },
    outputs = { "pkg": "%{name}.pkg" }
)


def macos_application_installer(**kwargs):
    """
    This macro builds an installer product
    """
    scripts = kwargs.pop("scripts")
    install_location = "/opt/XCBuildKit/XCBuildKit.app"
    mkargs = kwargs
    name = mkargs.pop("name")

    resources  = mkargs.pop("resources")
    distribution = mkargs.pop("distribution")

    native.filegroup(
        name = name + "_scripts",
        srcs = native.glob([scripts + "/*"])
    )

    macos_application_installer_pkg(
        name = name + "_impl",
        scripts=name + "_scripts",
        install_location=install_location,
        **mkargs
    )

    native.filegroup(
        name = name + "_resources",
        srcs = native.glob([resources + "/*"])
    )

    native.filegroup(
        name = name + "_distribution",
        srcs = native.glob([distribution])
    )

    macos_application_installer_product(
        name = name,
        distribution = name + "_distribution",
        resources = name + "_resources",
        version = "1.0",
        package = name + "_impl"
    )
