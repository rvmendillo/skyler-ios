import ProjectDescription

let project = Project(
    name: "UltraCompress",
    organizationName: "rvmendillo",
    packages: [
        .remote(url: "https://github.com/OlehKulykov/PLzmaSDK.git", requirement: .branch("master")),
        .remote(url: "https://github.com/weichsel/ZIPFoundation.git", requirement: .branch("development"))
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
                "CFBundleShortVersionString": "7.0",
                "CFBundleVersion": "7",
                "UILaunchScreen": [:],
                "LSSupportsOpeningDocumentsInPlace": true,
                "UIFileSharingEnabled": true,
                "NSDownloadsUbiquitousContents": true,
                "CFBundleDocumentTypes": [
                    [
                        "CFBundleTypeName": "iOS App Archive",
                        "CFBundleTypeRole": "Editor",
                        "LSHandlerRank": "Default",
                        "LSItemContentTypes": ["com.apple.itunes.ipa"]
                    ],
                    [
                        "CFBundleTypeName": "Compressible File",
                        "CFBundleTypeRole": "Editor",
                        "LSHandlerRank": "Alternate",
                        "LSItemContentTypes": [
                            "public.zip-archive",
                            "public.archive",
                            "public.data",
                            "public.content"
                        ]
                    ]
                ],
                "UTImportedTypeDeclarations": [
                    [
                        "UTTypeIdentifier": "com.apple.itunes.ipa",
                        "UTTypeDescription": "iOS App Archive",
                        "UTTypeConformsTo": ["public.data"],
                        "UTTypeTagSpecification": [
                            "public.filename-extension": ["ipa"],
                            "public.mime-type": ["application/x-ios-app"]
                        ]
                    ]
                ]
            ]),
            sources: ["SourcesV7/**"],
            resources: ["Resources/**"],
            dependencies: [
                .package(product: "PLzmaSDK"),
                .package(product: "ZIPFoundation")
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
