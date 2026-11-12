#!/usr/bin/env python3
"""Writes BillBox.xcodeproj (Xcode 16 or newer, iOS 18+) from the files on disk.  Run again after adding or removing a source file:
    python3 tools/make_xcodeproj.py
Targets:
  BillBox       the iPhone app: BillBox/**.swift + the engine (BillBoxCore/Sources/BillBoxCore)
  BillBoxTests  unit tests, no host app: the engine + ParityKit + BillMath + BillBoxCore/Tests/BillBoxCoreTests (golden answers from the Mac)"""
import hashlib, os, glob

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # ios/
os.chdir(ROOT)

def uid(*parts):
    return hashlib.md5('/'.join(parts).encode()).hexdigest()[:24].upper()

app_sources = sorted(glob.glob('BillBox/*/*.swift'))
core_sources = sorted(glob.glob('BillBoxCore/Sources/BillBoxCore/*.swift'))
test_sources = sorted(f for f in glob.glob('BillBoxCore/Tests/BillBoxCoreTests/*.swift') if not os.path.islink(f)) + ['BillBoxCore/Sources/ParityKit/ParityRunner.swift']
golden = 'BillBoxCore/Tests/BillBoxCoreTests/Golden'
assets = 'BillBox/Resources/Assets.xcassets'
pdfreader = 'BillBox/Resources/PDFReader'   # the Mac's PDF reader (pdf.js 1.10.100 + pdfExtract.js), a folder reference
plist = 'BillBox/Info.plist'

objs = {}   # id -> text
def add(i, text): objs[i] = text

# ---- file references and groups (mirroring folders)
groups = {}  # path -> (id, [child ids])
def group_for(path):
    if path in ('', '.'): return groups.setdefault('', (uid('group', 'root'), []))
    if path not in groups:
        groups[path] = (uid('group', path), [])
        parent = group_for(os.path.dirname(path))
        parent[1].append(groups[path][0])
    return groups[path]

def ftype(p):
    if p.endswith('.swift'): return 'sourcecode.swift'
    if p.endswith('.xcassets'): return 'folder.assetcatalog'
    if p.endswith('.plist'): return 'text.plist.xml'
    if p.endswith('.md'): return 'net.daringfireball.markdown'
    return 'folder'

fileref = {}
def ref(p):
    if p in fileref: return fileref[p]
    i = uid('ref', p)
    fileref[p] = i
    group_for(os.path.dirname(p))[1].append(i)
    add(i, f'{i} /* {os.path.basename(p)} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype(p)}; path = "{os.path.basename(p)}"; sourceTree = "<group>"; }};')
    return i

for p in app_sources + core_sources + test_sources + [golden, assets, pdfreader, plist, 'BillBox/Shared/BillMath.swift', 'FEATURE_PARITY.md', 'ARCHITECTURE.md', 'README.md']:
    if os.path.exists(p): ref(p)

# products
app_product, test_product = uid('product', 'app'), uid('product', 'tests')
add(app_product, f'{app_product} /* BillBox.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = BillBox.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
add(test_product, f'{test_product} /* BillBoxTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = BillBoxTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; }};')
products_group = uid('group', 'Products')
group_for('')[1].append(products_group)

def build_files(target, paths):
    ids = []
    for p in paths:
        i = uid('build', target, p)
        add(i, f'{i} /* {os.path.basename(p)} in {target} */ = {{isa = PBXBuildFile; fileRef = {fileref[p]} /* {os.path.basename(p)} */; }};')
        ids.append(i)
    return ids

def phase(kind, target, files):
    i = uid('phase', kind, target)
    lst = ''.join(f'\n\t\t\t\t{f},' for f in files)
    add(i, f'{i} /* {kind} */ = {{isa = PBX{kind}BuildPhase; buildActionMask = 2147483647; files = ({lst}\n\t\t\t); runOnlyForDeploymentPostprocessing = 0; }};')
    return i

app_src = phase('Sources', 'app', build_files('app', app_sources + core_sources))
app_res = phase('Resources', 'app', build_files('app', [assets, pdfreader]))
# ---- Swift packages: Pow (EmergeTools, MIT) for the dashboard and billing effects
pow_pkg, pow_dep, pow_build = uid('package', 'Pow'), uid('packagedep', 'app', 'Pow'), uid('build', 'app', 'Pow')
add(pow_pkg, f'{pow_pkg} /* XCRemoteSwiftPackageReference "Pow" */ = {{isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/EmergeTools/Pow"; requirement = {{kind = upToNextMajorVersion; minimumVersion = 1.0.0; }}; }};')
add(pow_dep, f'{pow_dep} /* Pow */ = {{isa = XCSwiftPackageProductDependency; package = {pow_pkg} /* XCRemoteSwiftPackageReference "Pow" */; productName = Pow; }};')
add(pow_build, f'{pow_build} /* Pow in Frameworks */ = {{isa = PBXBuildFile; productRef = {pow_dep} /* Pow */; }};')
app_fw = phase('Frameworks', 'app', [pow_build])
test_src = phase('Sources', 'tests', build_files('tests', core_sources + test_sources + ['BillBox/Shared/BillMath.swift']))
test_res = phase('Resources', 'tests', build_files('tests', [golden]))
test_fw = phase('Frameworks', 'tests', [])

common = {
    'IPHONEOS_DEPLOYMENT_TARGET': '18.0', 'SDKROOT': 'iphoneos', 'SWIFT_VERSION': '5.0', 'TARGETED_DEVICE_FAMILY': '1',
    'CLANG_ENABLE_MODULES': 'YES', 'ALWAYS_SEARCH_USER_PATHS': 'NO', 'ENABLE_STRICT_OBJC_MSGSEND': 'YES',
    'GCC_C_LANGUAGE_STANDARD': 'gnu11', 'MTL_FAST_MATH': 'YES', 'CODE_SIGN_STYLE': 'Automatic',
}
def settings_text(d):
    return ''.join(f'\n\t\t\t\t{k} = {v if v.replace("_","").isalnum() else chr(34)+v+chr(34)};' for k, v in sorted(d.items()))

def config(name, owner, d):
    i = uid('config', owner, name)
    add(i, f'{i} /* {name} */ = {{isa = XCBuildConfiguration; buildSettings = {{{settings_text(d)}\n\t\t\t}}; name = {name}; }};')
    return i

def config_list(owner, debug, release):
    i = uid('configlist', owner)
    add(i, f'{i} = {{isa = XCConfigurationList; buildConfigurations = (\n\t\t\t\t{debug} /* Debug */,\n\t\t\t\t{release} /* Release */,\n\t\t\t); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; }};')
    return i

proj_debug = config('Debug', 'project', {**common, 'DEBUG_INFORMATION_FORMAT': 'dwarf', 'ONLY_ACTIVE_ARCH': 'YES', 'SWIFT_OPTIMIZATION_LEVEL': '-Onone',
                                         'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'DEBUG', 'ENABLE_TESTABILITY': 'YES', 'GCC_OPTIMIZATION_LEVEL': '0'})
proj_release = config('Release', 'project', {**common, 'DEBUG_INFORMATION_FORMAT': 'dwarf-with-dsym', 'SWIFT_OPTIMIZATION_LEVEL': '-O',
                                             'SWIFT_COMPILATION_MODE': 'wholemodule', 'VALIDATE_PRODUCT': 'YES'})
proj_list = config_list('project', proj_debug, proj_release)

app_settings = {'PRODUCT_NAME': 'BillBox', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.local.billbox', 'INFOPLIST_FILE': plist,
                'MARKETING_VERSION': '14.11.0', 'CURRENT_PROJECT_VERSION': '13', 'ASSETCATALOG_COMPILER_APPICON_NAME': 'AppIcon',
                'ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME': 'AccentColor', 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @executable_path/Frameworks',
                'ENABLE_PREVIEWS': 'NO', 'DEVELOPMENT_TEAM': '', 'SUPPORTS_MACCATALYST': 'NO'}
app_list = config_list('app', config('Debug', 'app', app_settings), config('Release', 'app', app_settings))
test_settings = {'PRODUCT_NAME': 'BillBoxTests', 'PRODUCT_BUNDLE_IDENTIFIER': 'com.local.billbox.tests', 'GENERATE_INFOPLIST_FILE': 'YES',
                 'LD_RUNPATH_SEARCH_PATHS': '$(inherited) @loader_path/Frameworks @executable_path/Frameworks', 'DEVELOPMENT_TEAM': ''}
test_list = config_list('tests', config('Debug', 'tests', test_settings), config('Release', 'tests', test_settings))

app_target, test_target = uid('target', 'app'), uid('target', 'tests')
add(app_target, f'''{app_target} /* BillBox */ = {{isa = PBXNativeTarget; buildConfigurationList = {app_list}; buildPhases = (
				{app_src} /* Sources */,
				{app_fw} /* Frameworks */,
				{app_res} /* Resources */,
			); buildRules = (); dependencies = (); name = BillBox; packageProductDependencies = (
				{pow_dep} /* Pow */,
			); productName = BillBox; productReference = {app_product} /* BillBox.app */; productType = "com.apple.product-type.application"; }};''')
add(test_target, f'''{test_target} /* BillBoxTests */ = {{isa = PBXNativeTarget; buildConfigurationList = {test_list}; buildPhases = (
				{test_src} /* Sources */,
				{test_fw} /* Frameworks */,
				{test_res} /* Resources */,
			); buildRules = (); dependencies = (); name = BillBoxTests; productName = BillBoxTests; productReference = {test_product} /* BillBoxTests.xctest */; productType = "com.apple.product-type.bundle.unit-test"; }};''')

project = uid('project')
root_group = group_for('')[0]
add(project, f'''{project} /* Project object */ = {{isa = PBXProject; attributes = {{BuildIndependentTargetsInParallel = 1; LastSwiftUpdateCheck = 1420; LastUpgradeCheck = 1420; TargetAttributes = {{ {app_target} = {{CreatedOnToolsVersion = 14.2;}}; {test_target} = {{CreatedOnToolsVersion = 14.2;}}; }}; }};
			buildConfigurationList = {proj_list}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base, );
			mainGroup = {root_group}; packageReferences = (
				{pow_pkg} /* XCRemoteSwiftPackageReference "Pow" */,
			); productRefGroup = {products_group} /* Products */; projectDirPath = ""; projectRoot = ""; targets = (
				{app_target} /* BillBox */,
				{test_target} /* BillBoxTests */,
			); }};''')

# groups text
for path, (gid, children) in groups.items():
    kids = ''.join(f'\n\t\t\t\t{c},' for c in children)
    name = f'path = "{os.path.basename(path)}"; ' if path else ''
    add(gid, f'{gid} = {{isa = PBXGroup; children = ({kids}\n\t\t\t); {name}sourceTree = "<group>"; }};')
add(products_group, f'{products_group} /* Products */ = {{isa = PBXGroup; children = (\n\t\t\t\t{app_product},\n\t\t\t\t{test_product},\n\t\t\t); name = Products; sourceTree = "<group>"; }};')

out = '// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 56;\n\tobjects = {\n'
for i in sorted(objs): out += '\t\t' + objs[i] + '\n'
out += f'\t}};\n\trootObject = {project} /* Project object */;\n}}\n'
os.makedirs('BillBox.xcodeproj/project.xcworkspace', exist_ok=True)
open('BillBox.xcodeproj/project.pbxproj', 'w').write(out)
open('BillBox.xcodeproj/project.xcworkspace/contents.xcworkspacedata', 'w').write('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version = "1.0">\n   <FileRef location = "self:">\n   </FileRef>\n</Workspace>\n')

os.makedirs('BillBox.xcodeproj/xcshareddata/xcschemes', exist_ok=True)
ref_app = f'BuildableIdentifier = "primary" BlueprintIdentifier = "{app_target}" BuildableName = "BillBox.app" BlueprintName = "BillBox" ReferencedContainer = "container:BillBox.xcodeproj"'
ref_test = f'BuildableIdentifier = "primary" BlueprintIdentifier = "{test_target}" BuildableName = "BillBoxTests.xctest" BlueprintName = "BillBoxTests" ReferencedContainer = "container:BillBox.xcodeproj"'
open('BillBox.xcodeproj/xcshareddata/xcschemes/BillBox.xcscheme', 'w').write(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1420" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            <BuildableReference {ref_app}>
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            <BuildableReference {ref_test}>
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference {ref_app}>
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         <BuildableReference {ref_app}>
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
''')
print(f'BillBox.xcodeproj: {len(app_sources)} app + {len(core_sources)} engine sources; tests {len(test_sources)} files + Golden')
