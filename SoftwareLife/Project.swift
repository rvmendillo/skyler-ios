import ProjectDescription

let project = Project(
    name: "SoftwareLife",
    organizationName: "rvmendillo",
    targets: [
        .target(
            name: "SoftwareLife",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.rvmendillo.codecapital",
            deploymentTargets: .iOS("27.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "Code Capital",
                "UILaunchScreen": [:],
                "UIRequiresFullScreen": false,
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false
                ]
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [],
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
                "TARGETED_DEVICE_FAMILY": "1,2",
                "CODE_SIGN_STYLE": "Automatic"
            ])
        )
    ]
)
