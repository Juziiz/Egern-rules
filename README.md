# Egern 去广告规则

每日自动更新的 Egern 原生格式去广告规则集。

- **来源**: [blackmatrix7/ios_rule_script](https://github.com/blackmatrix7/ios_rule_script) 的 `Advertising`（Surge 版）
- **更新频率**: 每天 22:00 (CST) 通过 GitHub Actions 自动拉取上游并转换
- **规则数量**: 约 28 万条

## 在 Egern 中使用

添加规则集，URL 填写：

```
https://raw.githubusercontent.com/Juziiz/Egern-rules/main/egern/advertising.yaml
```

动作选择 **REJECT**。

## 手动触发更新

在仓库的 Actions 页面选择 "更新去广告规则" → Run workflow。
