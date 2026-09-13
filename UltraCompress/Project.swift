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
            deploymentTargets: .iOS("18.0"),
            infoPlist: .extendingDefault(with: [
                "CFBundleDisplayName": "UltraCompress",
                "CFBundleShortVersionString": "5.0",
                "CFBundleVersion": "5",
                "UILaunchScreen": [:],
                "LSSupportsOpeningDocumentsInPlace": true,
                "UIFileSharingEnabled": true,
                "CFBundleDocumentTypes": [
                    [
                        "CFBundleTypeName": "IPA / Archive / File",
                        "CFBundleTypeRole": "Editor",
                        "LSHandlerRank": "Alternate",
                        "LSItemContentTypes": [
                            "com.rvmendillo.ipa",
                            "public.zip-archive",
                            "public.archive",
                            "public.data",
                            "public.content"
                        ]
                    ]
                ],
                "UTImportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.rvmendillo.ipa",
                        "UTTypeDescription": "iOS App Archive",
                        "UTTypeConformsTo": ["public.zip-archive", "public.data"],
                        "UTTypeTagSpecification": [
                            "public.filename-extension": ["ipa"],
                            "public.mime-type": "application/octet-stream"
                        ]
                    ]
                ]
            ]),
            sources: ["SourcesV5/**"],
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
