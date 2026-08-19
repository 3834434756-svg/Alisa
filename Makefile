# Alisa - iOS AI 编程客户端构建脚本

# 默认目标：安装依赖
.PHONY: all setup deps xcodegen build test clean archive

all: deps xcodegen

# 安装 SPM 依赖
deps:
	xcodebuild -resolvePackageDependencies -project Alisa.xcodeproj -scheme Alisa

# 使用 XcodeGen 生成 .xcodeproj
xcodegen:
	xcodegen generate

# Debug 构建
build:
	xcodebuild build \
		-project Alisa.xcodeproj \
		-scheme Alisa \
		-destination 'generic/platform=iOS' \
		-configuration Debug \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO

# Release 构建
build-release:
	xcodebuild build \
		-project Alisa.xcodeproj \
		-scheme Alisa \
		-destination 'generic/platform=iOS' \
		-configuration Release \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO

# 运行测试
test:
	xcodebuild test \
		-project Alisa.xcodeproj \
		-scheme Alisa \
		-destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.0' \
		-testPlan Alisa

# 测试核心库
test-core:
	xcodebuild test \
		-project Alisa.xcodeproj \
		-scheme AlisaCore \
		-destination 'platform=iOS Simulator,name=iPhone 15 Pro,OS=17.0'

# 打包 IPA（需要配置签名）
archive:
	xcodebuild archive \
		-project Alisa.xcodeproj \
		-scheme Alisa \
		-archivePath build/Alisa.xcarchive \
		-configuration Release \
		CODE_SIGN_STYLE=Manual \
		PROVISIONING_PROFILE_SPECIFIER="" \
		DEVELOPMENT_TEAM=""

	@echo "IPA 导出..."
	xcodebuild -exportArchive \
		-archivePath build/Alisa.xcarchive \
		-exportPath build/Alisa.ipa \
		-exportOptionsPlist exportOptions.plist

# 构建并导出 .ipa（无签名，用于侧载）
build-unsigned:
	xcodebuild archive \
		-project Alisa.xcodeproj \
		-scheme Alisa \
		-archivePath build/Alisa.xcarchive \
		-configuration Release \
		CODE_SIGN_IDENTITY="" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=NO

	@echo "创建未签名 IPA..."
	mkdir -p build/Payload
	cp -r build/Alisa.xcarchive/Products/Applications/Alisa.app build/Payload/
	cd build && zip -r Alisa-unsigned.ipa Payload
	rm -rf build/Payload build/Alisa.xcarchive
	@echo "IPA 已生成: build/Alisa-unsigned.ipa"

# 清理
clean:
	rm -rf build/
	rm -rf ~/Library/Developer/Xcode/DerivedData/Alisa-*
	xcodebuild clean -project Alisa.xcodeproj -scheme Alisa

# 安装 Fastlane 并配置
setup-fastlane:
	gem install fastlane --no-document
	fastlane init

# 代码检查
lint:
	swiftlint lint --strict

format:
	swiftformat --swiftversion 6.0 Sources/