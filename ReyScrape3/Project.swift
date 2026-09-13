import ProjectDescription

let project = Project(
    name: "ReyScrape3",
    organizationName: "RVMendillo",
    targets: [
        .target(
            name: "ReyScrape3",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.rvmendillo.reyscrape",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "ReyScrape",
                "CFBundleShortVersionString": "3.1",
                "CFBundleVersion": "310",
                "UILaunchScreen": [:],
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false
                ]
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            settings: .settings(base: [
                "SWIFT_VERSION": "5.10",
                "CODE_SIGN_STYLE": "Automatic",
                "TARGETED_DEVICE_FAMILY": "1,2",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
                "ENABLE_USER_SCRIPT_SANDBOXING": "NO"
            ])
        )
    ]
)
