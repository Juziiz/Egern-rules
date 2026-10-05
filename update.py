#!/usr/bin/env python3
"""每日更新 Egern 去广告规则:
   blackmatrix7/ios_rule_script (Surge) -> Egern 原生 YAML -> 提交到本仓库
   由 GitHub Actions 定时运行。
"""
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

UPSTREAMS = [
    "https://cdn.jsdelivr.net/gh/blackmatrix7/ios_rule_script@master/rule/Surge/Advertising/Advertising_All.list",
    "https://raw.githubusercontent.com/blackmatrix7/ios_rule_script/master/rule/Surge/Advertising/Advertising_All.list",
]

OUT_PATH = Path(__file__).resolve().parent / "egern" / "advertising.yaml"


def fetch_upstream():
    last_err = None
    for url in UPSTREAMS:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "egern-rules-updater/1.0"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                return resp.read().decode("utf-8", errors="replace"), url
        except Exception as e:
            last_err = e
    raise SystemExit(f"上游拉取失败: {last_err}")


def convert(text):
    domains, suffixes, keywords, cidrs = set(), set(), set(), set()
    upstream_updated = ""
    for line in text.split("\n"):
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            if line.startswith("# UPDATED:"):
                upstream_updated = line.split(":", 1)[1].strip()
            continue
        comma = line.find(",")
        if comma == -1:
            continue
        rtype = line[:comma].strip().upper()
        value = line[comma + 1:].strip()
        if not value:
            continue
        if rtype == "DOMAIN":
            domains.add(value)
        elif rtype == "DOMAIN-SUFFIX":
            suffixes.add(value.lstrip("."))
        elif rtype == "DOMAIN-KEYWORD":
            keywords.add(value)
        elif rtype in ("IP-CIDR", "IP-CIDR6"):
            cidrs.add(value)
        # 跳过 AND / URL-REGEX 等 Egern 规则集不支持的类型
    return domains, suffixes, keywords, cidrs, upstream_updated


def build_yaml(domains, suffixes, keywords, cidrs, upstream_updated):
    total = len(domains) + len(suffixes) + len(keywords) + len(cidrs)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    out = []
    out.append("# 规则名称: Advertising")
    out.append(f"# 规则统计: {total}")
    out.append("# 来源: blackmatrix7/ios_rule_script (Surge)")
    out.append(f"# 上游更新: {upstream_updated or 'unknown'}")
    out.append(f"# 转换时间: {now}")
    out.append("")
    out.append("no_resolve: true")
    if domains:
        out.append("domain_set:")
        out.extend(f"  - {d}" for d in sorted(domains))
    if suffixes:
        out.append("domain_suffix_set:")
        out.extend(f"  - {d}" for d in sorted(suffixes))
    if keywords:
        out.append("domain_keyword_set:")
        out.extend(f"  - {d}" for d in sorted(keywords))
    if cidrs:
        out.append("ip_cidr_set:")
        out.extend(f"  - {d}" for d in sorted(cidrs))
    return "\n".join(out) + "\n", total, now


def main():
    text, src = fetch_upstream()
    print(f"上游拉取成功: {src} ({len(text)} 字节)")
    domains, suffixes, keywords, cidrs, upstream_updated = convert(text)
    yaml_text, total, now = build_yaml(domains, suffixes, keywords, cidrs, upstream_updated)
    print(f"转换完成: domain={len(domains)} suffix={len(suffixes)} "
          f"keyword={len(keywords)} cidr={len(cidrs)} total={total}")
    OUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUT_PATH.write_text(yaml_text, encoding="utf-8")
    print(f"已写入: {OUT_PATH} ({len(yaml_text.encode('utf-8'))} 字节)")


if __name__ == "__main__":
    main()
