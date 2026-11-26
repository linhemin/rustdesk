# 远程桌面的中继和直连选路

## 会话怎样建立

在新版控制端、被控端和 hbbs 上，允许直连的公网桌面会话可以先从中继取画面。控制端核对 hbbs 签过的被控端身份，并通过中继完成端到端握手。已配对的中继不可用时，控制端重新走普通连接流程，本轮有其他已测中继时会优先尝试其他节点。局域网和仅直连策略保留直接建立会话的入口。

一个 hbbs 可以公布多个分布在不同地域的 hbbr。控制端与被控端各自通过受信的 hbbs 获取节点名单，并行向候选节点发送一次带随机数的应用层回显。双方都有数据时选取两段实测往返时间之和最小的共同节点。两端通过同一节点配对。手动指定中继时优先使用手动配置。节点不足、超时或旧版未提供测量时，仍可按原有服务端策略连接。部署示例在 rustdesk-server-direct 仓库的 `deploy/regional-relays/`。

## 会话中怎样切换

两端在已认证的桌面会话里协商质量探测。TCP、UDP 和 WebRTC 各自尝试，经打通的 TCP 连接也可协商 WebSocket 握手。同一 TCP 映射上的原生 TCP 和 WebSocket 分轮尝试。WebRTC 使用 ICE、DTLS 和数据通道，选到 TURN 的连接按中继处理。配置了应用内代理或显式强制中继时遵循相应策略。

候选要先通过双向回显。两端都支持新的质量协议时，控制端比较同样大小的回显，结合往返时间及波动决定是否接管。静止桌面也能取样。直连变差时继续用保留的中继，切换过程中通过序号确认已传输的数据。小包回显给出响应速度和波动，无法直接给出视频可用吞吐量。

## 修改某条路径时

| 负责的行为 | 对应模块 |
| --- | --- |
| 区域目录校验、分节点回显、两段时延合并 | `src/p2p/regional_relay.rs` |
| 初次中继配对与失败后的候选过滤 | `src/client/relay_start.rs` |
| TCP 和 QUIC 中继的建立时序 | `src/p2p/relay.rs` |
| TCP 打洞 | `src/p2p/tcp.rs` |
| 原生 UDP 映射、对端候选和探测 | `src/p2p/ordinary_udp.rs`、`src/p2p/udp_paths.rs` |
| 已打通 TCP 上的 WebSocket 升级、绑回原会话 | `src/live_direct/native/websocket.rs`、`libs/hbb_common/src/websocket/peer.rs` |
| WebRTC 候选通道与连接状态 | `src/live_direct/webrtc_path.rs` |
| 中继与直连的测量、接管与回退 | `src/live_direct/quality.rs`、`src/live_direct/parallel.rs` |
| 已登记设备经 TCP 或 WSS 接收会合消息 | `src/rendezvous_mediator/device_stream.rs`、服务端 `src/device_stream.rs` |

公网验收时，每次保留网络类型、VPN 状态、两端版本、首帧时间、选中的中继和最终媒体路径。成功建立直连、直连质量优于中继、实际切换成功是三项可以分别计数的结果。
