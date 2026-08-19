#!/usr/bin/env python3
import os
import plistlib
import uuid

PROJECT_DIR = os.getcwd()
PROJECT_NAME = "Alisa"

def gen_id():
    return uuid.uuid4().hex.upper()

# Root object IDs
root_id = gen_id()
main_group_id = gen_id()
products_group_id = gen_id()
app_group_id = gen_id()
core_group_id = gen_id()
ui_group_id = gen_id()
source_packages_group_id = gen_id()

# Build configuration list IDs
build_config_list_id = gen_id()
project_build_config_id = gen_id()
project_build_config_release_id = gen_id()

# Target IDs
app_target_id = gen_id()
core_target_id = gen_id()
ui_target_id = gen_id()

# Build configuration list IDs for targets
app_build_config_list_id = gen_id()
core_build_config_list_id = gen_id()
ui_build_config_list_id = gen_id()

# Build configuration IDs
app_debug_id = gen_id()
app_release_id = gen_id()
core_debug_id = gen_id()
core_release_id = gen_id()
ui_debug_id = gen_id()
ui_release_id = gen_id()

# Build phase IDs
app_sources_phase_id = gen_id()
app_frameworks_phase_id = gen_id()
app_resources_phase_id = gen_id()
core_sources_phase_id = gen_id()
core_frameworks_phase_id = gen_id()
ui_sources_phase_id = gen_id()
ui_frameworks_phase_id = gen_id()

# Source file IDs
def get_source_files(base_dir, prefix=""):
    files = []
    for root, dirs, filenames in os.walk(os.path.join(PROJECT_DIR, base_dir)):
        for f in filenames:
            if f.endswith('.swift') or f.endswith('.plist'):
                rel_path = os.path.relpath(os.path.join(root, f), PROJECT_DIR)
                files.append(rel_path)
    return sorted(files)

app_files = get_source_files("Sources/App")
core_files = get_source_files("Sources/Core")
ui_files = get_source_files("Sources/UI")

# Build file references
def make_file_refs(file_list, source_tree='<group>'):
    refs = {}
    for f in file_list:
        ref_id = gen_id()
        refs[f] = ref_id
    return refs

app_file_refs = make_file_refs(app_files)
core_file_refs = make_file_refs(core_files)
ui_file_refs = make_file_refs(ui_files)

# Build file IDs
def make_build_files(file_refs):
    return {path: gen_id() for path in file_refs}

app_build_files = make_build_files(app_file_refs)
core_build_files = make_build_files(core_file_refs)
ui_build_files = make_build_files(ui_file_refs)

# Package references
package_refs = {
    "GRDB": gen_id(),
    "ZIPFoundation": gen_id(),
    "GCDWebServer": gen_id(),
    "Highlightr": gen_id()
}

# Package product IDs
package_products = {
    "GRDB": gen_id(),
    "ZIPFoundation": gen_id(),
    "GCDWebServer": gen_id(),
    "Highlightr": gen_id()
}

objects = {}

# Build configuration
objects[project_build_config_id] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    },
    "name": "Debug"
}

objects[project_build_config_release_id] = {
    "isa": "XCBuildConfiguration",
    "buildSettings": {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    },
    "name": "Release"
}

objects[build_config_list_id] = {
    "isa": "XCConfigurationList",
    "buildConfigurations": [project_build_config_id, project_build_config_release_id],
    "defaultConfigurationIsVisible": 0,
    "defaultConfigurationName": "Release"
}

# Source root PBXGroup
objects[main_group_id] = {
    "isa": "PBXGroup",
    "children": [app_group_id, core_group_id, ui_group_id, products_group_id, source_packages_group_id],
    "sourceTree": "<group>",
    "name": ""
}

# Source groups
for group_id, group_name, files in [
    (app_group_id, "App", app_files),
    (core_group_id, "Core", core_files),
    (ui_group_id, "UI", ui_files)
]:
    children = []
    for f in files:
        if f in app_file_refs:
            rid = app_file_refs[f]
        elif f in core_file_refs:
            rid = core_file_refs[f]
        else:
            rid = ui_file_refs[f]
        objects[rid] = {
            "isa": "PBXFileReference",
            "lastKnownFileType": "sourcecode.swift" if f.endswith('.swift') else "text.plist.xml",
            "path": os.path.basename(f) if "/" not in f else f,
            "sourceTree": "<group>",
            "name": os.path.basename(f)
        }
        children.append(rid)

    objects[group_id] = {
        "isa": "PBXGroup",
        "children": children,
        "sourceTree": "<group>",
        "name": group_name
    }

# Products group
objects[products_group_id] = {
    "isa": "PBXGroup",
    "children": [app_target_id, core_target_id, ui_target_id],
    "sourceTree": "<group>",
    "name": "Products"
}

# Package references
package_urls = {
    "GRDB": "https://github.com/groue/GRDB.swift.git",
    "ZIPFoundation": "https://github.com/weichsel/ZIPFoundation.git",
    "GCDWebServer": "https://github.com/swisspol/GCDWebServer.git",
    "Highlightr": "https://github.com/raspu/Highlightr.git"
}

package_versions = {
    "GRDB": "6.29.0",
    "ZIPFoundation": "0.9.19",
    "GCDWebServer": "3.5.4",
    "Highlightr": "2.1.0"
}

objects[source_packages_group_id] = {
    "isa": "PBXGroup",
    "children": list(package_refs.values()),
    "sourceTree": "<group>",
    "name": "Packages"
}

for pkg_name, pkg_id in package_refs.items():
    objects[pkg_id] = {
        "isa": "XCRemoteSwiftPackageReference",
        "repositoryURL": package_urls[pkg_name],
        "requirement": {
            "kind": "upToNextMajorVersion",
            "minimumVersion": package_versions[pkg_name]
        }
    }

# Package product references
for pkg_name, prod_id in package_products.items():
    pkg_id = package_refs[pkg_name]
    objects[prod_id] = {
        "isa": "XCSwiftPackageProductDependency",
        "productName": pkg_name,
        "package": pkg_id
    }

# PBXFileReference for product references
objects[app_target_id] = {
    "isa": "PBXFileReference",
    "path": "Alisa.app",
    "sourceTree": "BUILT_PRODUCTS_DIR"
}
objects[core_target_id] = {
    "isa": "PBXFileReference",
    "path": "AlisaCore.framework",
    "sourceTree": "BUILT_PRODUCTS_DIR"
}
objects[ui_target_id] = {
    "isa": "PBXFileReference",
    "path": "AlisaUI.framework",
    "sourceTree": "BUILT_PRODUCTS_DIR"
}

# Build phases
def make_sources_phase(phase_id, build_file_map):
    files = [{"fileRef": ref_id} for ref_id in build_file_map.values()]
    objects[phase_id] = {
        "isa": "PBXSourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": files,
        "runOnlyForDeploymentPostprocessing": 0
    }

def make_frameworks_phase(phase_id, deps=None):
    entries = []
    if deps:
        for dep in deps:
            entries.append({"fileRef": dep})
    objects[phase_id] = {
        "isa": "PBXFrameworksBuildPhase",
        "buildActionMask": 2147483647,
        "files": entries,
        "runOnlyForDeploymentPostprocessing": 0
    }

def make_resources_phase(phase_id):
    objects[phase_id] = {
        "isa": "PBXResourcesBuildPhase",
        "buildActionMask": 2147483647,
        "files": [],
        "runOnlyForDeploymentPostprocessing": 0
    }

# Create build files for each source file
for path, ref_id in app_file_refs.items():
    objects[app_build_files[path]] = {
        "isa": "PBXBuildFile",
        "fileRef": ref_id
    }
for path, ref_id in core_file_refs.items():
    objects[core_build_files[path]] = {
        "isa": "PBXBuildFile",
        "fileRef": ref_id
    }
for path, ref_id in ui_file_refs.items():
    objects[ui_build_files[path]] = {
        "isa": "PBXBuildFile",
        "fileRef": ref_id
    }

# Build phases
make_sources_phase(app_sources_phase_id, app_build_files)
make_frameworks_phase(app_frameworks_phase_id)
make_resources_phase(app_resources_phase_id)

make_sources_phase(core_sources_phase_id, core_build_files)
make_frameworks_phase(core_frameworks_phase_id, [package_products["GRDB"], package_products["ZIPFoundation"], package_products["GCDWebServer"]])

make_sources_phase(ui_sources_phase_id, ui_build_files)
make_frameworks_phase(ui_frameworks_phase_id, [package_products["Highlightr"]])

# Target build configurations
for cfg_id, cfg_name, extra in [
    (app_debug_id, "Debug", {"PRODUCT_BUNDLE_IDENTIFIER": "com.alisa.app", "INFOPLIST_FILE": "Info.plist", "PRODUCT_NAME": "Alisa", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}),
    (app_release_id, "Release", {"PRODUCT_BUNDLE_IDENTIFIER": "com.alisa.app", "INFOPLIST_FILE": "Info.plist", "PRODUCT_NAME": "Alisa"}),
    (core_debug_id, "Debug", {"PRODUCT_BUNDLE_IDENTIFIER": "com.alisa.core", "PRODUCT_NAME": "AlisaCore", "SKIP_INSTALL": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}),
    (core_release_id, "Release", {"PRODUCT_BUNDLE_IDENTIFIER": "com.alisa.core", "PRODUCT_NAME": "AlisaCore", "SKIP_INSTALL": "YES"}),
    (ui_debug_id, "Debug", {"PRODUCT_BUNDLE_IDENTIFIER": "com.alisa.ui", "PRODUCT_NAME": "AlisaUI", "SKIP_INSTALL": "YES", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}),
    (ui_release_id, "Release", {"PRODUCT_BUNDLE_IDENTIFIER": "com.alisa.ui", "PRODUCT_NAME": "AlisaUI", "SKIP_INSTALL": "YES"})
]:
    settings = {
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "YES",
        "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
        "MARKETING_VERSION": "1.0.0",
        "SWIFT_VERSION": "6.0",
        "TARGETED_DEVICE_FAMILY": "1,2",
    }
    settings.update(extra)
    objects[cfg_id] = {
        "isa": "XCBuildConfiguration",
        "buildSettings": settings,
        "name": cfg_name
    }

# Build configuration lists
for list_id, config_ids in [
    (app_build_config_list_id, [app_debug_id, app_release_id]),
    (core_build_config_list_id, [core_debug_id, core_release_id]),
    (ui_build_config_list_id, [ui_debug_id, ui_release_id])
]:
    objects[list_id] = {
        "isa": "XCConfigurationList",
        "buildConfigurations": config_ids,
        "defaultConfigurationIsVisible": 0,
        "defaultConfigurationName": "Release"
    }

# Targets
objects[app_target_id] = {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": app_build_config_list_id,
    "buildPhases": [app_sources_phase_id, app_frameworks_phase_id, app_resources_phase_id],
    "buildRules": [],
    "dependencies": [
        {"target": core_target_id, "targetProxy": gen_id()},
        {"target": ui_target_id, "targetProxy": gen_id()}
    ],
    "name": "Alisa",
    "productName": "Alisa",
    "productReference": app_target_id,
    "productType": "com.apple.product-type.application"
}

objects[core_target_id] = {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": core_build_config_list_id,
    "buildPhases": [core_sources_phase_id, core_frameworks_phase_id],
    "buildRules": [],
    "dependencies": [],
    "name": "AlisaCore",
    "productName": "AlisaCore",
    "productReference": core_target_id,
    "productType": "com.apple.product-type.framework"
}

objects[ui_target_id] = {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": ui_build_config_list_id,
    "buildPhases": [ui_sources_phase_id, ui_frameworks_phase_id],
    "buildRules": [],
    "dependencies": [
        {"target": core_target_id, "targetProxy": gen_id()}
    ],
    "name": "AlisaUI",
    "productName": "AlisaUI",
    "productReference": ui_target_id,
    "productType": "com.apple.product-type.framework"
}

# Root object
objects[root_id] = {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": 1,
        "LastUpgradeCheck": "1600",
    },
    "buildConfigurationList": build_config_list_id,
    "compatibilityVersion": "Xcode 14.0",
    "developmentRegion": "zh-Hans",
    "hasScannedForEncodings": 0,
    "knownRegions": ["en", "zh-Hans"],
    "mainGroup": main_group_id,
    "productRefGroup": products_group_id,
    "packageReferences": list(package_refs.values()),
    "packageDependencies": [],
    "projectDirPath": "",
    "projectRoot": "",
    "targets": [app_target_id, core_target_id, ui_target_id]
}

pbxproj = {
    "archiveVersion": 1,
    "classes": {},
    "objectVersion": 60,
    "objects": objects,
    "rootObject": root_id
}

# Create the xcodeproj directory
xcodeproj_path = os.path.join(PROJECT_DIR, f"{PROJECT_NAME}.xcodeproj")
os.makedirs(xcodeproj_path, exist_ok=True)

# Write project.pbxproj
pbxproj_file = os.path.join(xcodeproj_path, "project.pbxproj")
with open(pbxproj_file, 'wb') as f:
    plistlib.dump(pbxproj, f, fmt=plistlib.FMT_XML)

print(f"Created Xcode project at {xcodeproj_path}")
print(f"  - App target: {app_target_id}")
print(f"  - Core target: {core_target_id}")
print(f"  - UI target: {ui_target_id}")
print(f"  - Source files: {len(app_files) + len(core_files) + len(ui_files)}")
print(f"  - Packages: {list(package_refs.keys())}")