/**
 * TestFlight 名额监控（Surge 版）
 * 由 Egern 版移植，原作者：IBL3ND/module（TestFlight.js「极速疯狗版」）
 * 功能：定时检查 TestFlight 公开链接，页面不再显示「已满」且出现加入入口时立刻弹窗通知，点通知直达加入页
 * 行为：有名额时会每一轮都通知（原版设计如此），抢到后把脚本停用即可
 *
 * 用法（二选一）：
 * 1) 订阅模块版（推荐）：参数表里可改监控目标 TF 与检查周期 CRON
 *    - 每秒（疯狗模式）：CRON 填六段式 * * * * * *（会触发 Surge 耗电警告）
 *    - 每分钟：* * * * * ；每5分钟：*\/5 * * * * ；每小时：0 * * * *
 * 2) 手动新建脚本：类型选 Cron，表达式同上，粘贴本文件全部代码，保存
 *    配置/模块 [Script] 引用示例：
 *    TF名额监控 = type=cron, cronexp="* * * * *", script-path=本文件地址, argument="TF=VCIvwk2g", timeout=30
 *
 * 监控目标：默认已填 QX（VCIvwk2g）。改目标两种方式：
 * - 改下方 CONFIG_IDS，每项格式：邀请码 或 邀请码@应用名，多个用英文逗号隔开
 * - 或用 argument 传入：argument=TF=邀请码1,邀请码2@应用名（优先级高于 CONFIG_IDS）
 */

// 默认监控列表（已预填 Quantumult X）
const CONFIG_IDS = "VCIvwk2g@Quantumult X";

// 已知邀请码对应的应用名（argument 只传码时用它补名字）
const KNOWN_NAMES = { "VCIvwk2g": "Quantumult X" };

const userAgents = [
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 11_6_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 12_4) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_1) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 11_7_9) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 12_6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 13_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36"
];

function parseIds() {
  let raw = "";
  try {
    if (typeof $argument !== "undefined" && $argument) {
      const m = String($argument).match(/(?:^|&)TF=([^&]*)/);
      if (m) raw = decodeURIComponent(m[1]);
    }
  } catch (e) {}
  if (!raw) raw = CONFIG_IDS;
  return raw
    .split(/\s*[,，;]\s*/)
    .filter(Boolean)
    .map(s => {
      const parts = s.split("@");
      const id = (parts[0] || "").trim();
      const name = (parts[1] || "").trim() || KNOWN_NAMES[id] || "";
      return { id: id, name: name };
    })
    .filter(x => x.id);
}

function httpGet(url, ua) {
  return new Promise((resolve, reject) => {
    $httpClient.get(
      { url: url, headers: { "User-Agent": ua }, timeout: 10000 },
      (err, resp, data) => {
        if (err) reject(err);
        else resolve({ status: resp.status, data: data || "" });
      }
    );
  });
}

(async () => {
  const ids = parseIds();
  const getRandomUA = () => userAgents[Math.floor(Math.random() * userAgents.length)];

  console.log(`[TF Monitor] 开始检查：[${ids.map(x => x.id).join(", ")}]`);

  for (const item of ids) {
    const appId = item.id;
    const appName = item.name;
    const url = `https://testflight.apple.com/join/${appId}`;

    try {
      const res = await httpGet(url, getRandomUA());

      if (res.status === 404) {
        console.log(`[D] ${appId} → 不存在 ⚠️`);
      } else if (res.status !== 200) {
        console.log(`[?] ${appId} → 状态码: ${res.status}`);
      } else if (/版本的测试员已满|This beta is full|此 beta 版已额满/.test(res.data)) {
        console.log(`[F] ${appId} → 已满`);
      } else if (/版本目前不接受任何新测试员|This beta isn't accepting any new testers/.test(res.data)) {
        console.log(`[N] ${appId} → 暂不接受新成员`);
      } else if (/要加入 Beta 版|To join the|开始测试|itms-beta:\/\/|join the beta/.test(res.data)) {
        console.log(`[Y] ${appId} → 可加入 ✅`);
        $notification.post(
          "TestFlight 有名额了！",
          appName ? `${appName} (${appId})` : `ID: ${appId}`,
          "🚀 探测到新名额，请立即点击加入测试",
          { action: "open-url", url }
        );
      } else {
        console.log(`[?] ${appId} → 状态未知`);
      }
    } catch (e) {
      console.log(`[!] ${appId} → 请求出错: ${e && e.message ? e.message : e}`);
    }

    await new Promise(r => setTimeout(r, 500));
  }

  $done();
})();
