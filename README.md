# 电子衣橱

一个完全本地的 iOS 电子衣橱 App：不用注册、不联网，照片和数据只存在手机上。

## 功能

- **批量导入**：从相册一次多选很多张衣服照片
- **自动抠图**：后台逐张用系统 Vision 识别主体、去掉背景（与相册"长按抠图"同一套能力，本机完成）
- **待分类**：抠好的图逐张或批量归类到大类 / 小类，并标上季节等标签
- **自定义分类**：大类、小类、标签都可以新增、改名、删除、排序
- **每日穿搭**：从衣橱里选当天穿的衣服，自动拼成一张图
- **日历**：按周、按月查看每天穿了什么

## 运行

需要 Xcode 15+、iOS 17+，以及 [XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
xcodegen generate
open Wardrobe.xcodeproj
```

在 Xcode 的 Signing & Capabilities 里选自己的 Team，必要时把 Bundle ID 改成自己的，然后运行到真机或模拟器。抠图在真机上效果最好。

## 结构

```
Wardrobe/
├── Models/        数据模型（SwiftData）
├── Services/      图片存储、抠图、导入队列、拼图
└── Views/         衣橱、待分类、分类管理、穿搭、日历
```
