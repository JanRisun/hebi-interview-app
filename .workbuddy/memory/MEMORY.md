# HebiInterviewApp - 项目长期记忆

## 语音识别（Core Speech Kit）硬约束
- **仅支持离线识别** `online:1`。无云侧模式；AGC 无"云侧语音识别"服务。切勿尝试 `online:0`（createEngine 直接报错）。
- 离线 ASR 依赖两项设备能力：① 已下载「中文离线语音模型」（系统设置→智慧语音）；② **HiAI 推理运行时**（libhiai_*）。任一缺失则 createEngine 失败。
- 日志出现 `libhiai_ir_infershape.so failed` = 设备离线推理运行时缺失/损坏，连系统小艺离线识别也失败 → 纯设备/固件问题，非代码。
- 代码现状：RecorderBar.ets（实时字幕，AudioCapturer 双路喂 writeAudio）、AsrHelper.ets（文件转文字）均 online:1；均有「手动录入文字稿」兜底。
- writeAudio 块长仅 640/1280 字节；须先 startListening 成功(onStart)再 writeAudio；recognitionMode:1(long) 支持超 60s；maxAudioDuration 默认 20000ms(已设 600000)。

## 已知设备坑
- 畅享系列测试机（90pro max）：libhiai 运行时缺失，离线 ASR 不可用。自动转写真机验证需换 Mate/P 等离线运行时正常的设备。

## 功能缺口
- AudioAnswer.ets（"音频作答"大圆钮页）仅录音+波形，无实时字幕；若要"录音机那种"体验需接入 RecorderBar 的实时 ASR 链路。
