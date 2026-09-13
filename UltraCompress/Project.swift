import ProjectDescription

let project = Project(
    name: "UltraCompress",
    organizationName: "rvmendillo",
    packages: [
        .remote(url: "https://github.com/OlehKulykov/PLzmaSDK.git", requirement: .branch("master")),
        .remote(url: "https://github.com/tomasf/Zip.git", requirement: .branch("main"))
    ],
    targets: [
        .target(
            name: "UltraCompress",
            destinations: [.iPhone, .iPad],
            product: .app,
            bundleId: "com.rvmendillo.ultracompress",
            deploymentTargets: .iOS("27.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "UltraCompress",
                "UILaunchScreen": [:],
                "LSSupportsOpeningDocumentsInPlace": true,
                "UIFileSharingEnabled": true,
                "CFBundleDocumentTypes": [
                    [
                        "CFBundleTypeName": "Compressible File",
                        "CFBundleTypeRole": "Editor",
                        "LSHandlerRank": "Alternate",
                        "LSItemContentTypes": ["public.data", "public.archive", "public.folder"]
                    ]
                ]
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [
                .package(product: "PLzmaSDK"),
                .package(product: "Zip")
            ],
            settings: .settings(base: [
                "SWIFT_VERSION": "6.0",
                "TARGETED_DEVICE_FAMILY": "1,2",
                "CODE_SIGN_STYLE": "Automatic",
                "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon"
            ])
        )
    ]
)
