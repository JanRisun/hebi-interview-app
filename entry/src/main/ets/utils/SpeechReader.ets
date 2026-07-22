// 语音朗读封装：基于 @kit.SpeechKit 的系统朗读控件 TextReader。
// 取代原自研方案（TtsManager / TtsButton / TtsFloatButton）——
// TextReader 自带系统朗读面板（悬浮播控条 + 进度 + 倍速 + 音色），
// 因此无需再自绘"悬浮按钮"，页面内只保留一个触发图标 ReaderIcon。
//
// 接入要点：
//   1) EntryAbility.onWindowStageCreate 中先调用 WindowManager.setWindowStage(windowStage)；
//   2) 页面里放置 ReaderIcon({ id, title, text })，点击即开始朗读 / 拉起面板。
//
// 状态同步：TextReader.on('stateChange') 是全局回调，这里把「当前活跃朗读 id + 状态」
// 写进 AppStorage；各 ReaderIcon 通过比对自身 id 决定图标状态，避免多图标状态串扰。
import { TextReader, TextReaderIcon, ReadStateCode } from '@kit.SpeechKit';
import { common } from '@kit.AbilityKit';
import { FONT, RADIUS, SPACE } from './Theme';

// AppStorage keys：当前活跃朗读的文章 id / 当前朗读状态 / 当前活跃文章播放进度（百分比）
const K_ACTIVE_ID: string = 'readerActiveId';
const K_STATE: string = 'readerState';
const K_PROGRESS: string = 'readerProgress';

class SpeechReaderImpl {
  private inited: boolean = false;
  private initPromise: Promise<void> | undefined = undefined;

  // 幂等初始化：首次真正 init + 注册全局监听；并发调用共享同一 Promise
  async ensureInit(context: common.Context): Promise<void> {
    if (this.inited) {
      return;
    }
    if (this.initPromise) {
      await this.initPromise;
      return;
    }
    this.initPromise = this.doInit(context);
    await this.initPromise;
  }

  private async doInit(context: common.Context): Promise<void> {
    // keepBackgroundRunning=true：配合 module.json5 中的
    // ohos.permission.KEEP_BACKGROUND_RUNNING 权限与 EntryAbility 的
    // backgroundModes:["audioPlayback"]，让 TextReader 在 App 切到后台时
    // 自动保持朗读（系统内部起后台长时任务），避免后台被打断。
    const readerParam: TextReader.ReaderParam = {
      isVoiceBrandVisible: true,
      keepBackgroundRunning: true,
      businessBrandInfo: {
        panelName: '语音朗读',
        panelIcon: $r('app.media.app_icon')
      }
    };
    await TextReader.init(context, readerParam);
    // 朗读状态变化：写入 AppStorage 供各 ReaderIcon 图标同步。
    TextReader.on('stateChange', (state: TextReader.ReadState) => {
      AppStorage.setOrCreate(K_ACTIVE_ID, state.id);
      AppStorage.setOrCreate(K_STATE, state.state);
    });
    // 朗读进度变化：仅在进度属于当前活跃文章时广播百分比，
    // 供各 ReaderIcon 显示播放进度（SDK 仅提供百分比，不含秒级时长）。
    TextReader.on('readProgress', (p: TextReader.ReadProgress) => {
      if (p.id === AppStorage.get<string>(K_ACTIVE_ID)) {
        AppStorage.setOrCreate(K_PROGRESS, p.currentPercent);
      }
    });
    // 朗读到列表末尾时系统会请求更多内容；本应用无分页，回传空表并置 isEnd=true
    TextReader.on('requestMore', () => {
      TextReader.loadMore([], true);
    });
    this.inited = true;
  }

  // 朗读指定内容：若正在朗读同一条则拉起系统面板，否则从头开始朗读
  async play(context: common.Context, id: string, title: string, text: string): Promise<void> {
    await this.ensureInit(context);
    const info: TextReader.ReadInfo = {
      id: id,
      title: { text: title, isClickable: false },
      bodyInfo: text
    };
    const activeId: string = AppStorage.get<string>(K_ACTIVE_ID) ?? '';
    const st: ReadStateCode | undefined = AppStorage.get<ReadStateCode>(K_STATE);
    if (activeId === id && st === ReadStateCode.PLAYING) {
      TextReader.showPanel();
    } else {
      await TextReader.start([info], id);
    }
  }
}

// 全局单例：多个 ReaderIcon 共享同一朗读引擎与系统面板
export const SpeechReader: SpeechReaderImpl = new SpeechReaderImpl();

// 可复用朗读入口：系统朗读图标（自带播放/加载/暂停动效）+ 可选文案，做成轻药丸。
// 点击开始朗读对应内容；正在朗读同一条时点击拉起系统朗读面板。
@Component
export struct ReaderIcon {
  @Prop @Watch('syncReadState') readId: string = '';    // 内容唯一标识（用于状态匹配，需全局唯一，避免与内置 id() 冲突）
  @Prop title: string = '';     // 系统面板标题
  @Prop text: string = '';      // 朗读正文
  @Prop label: string = '';     // 可选：图标右侧文案（如"朗读全文"）
  // TextReaderIcon 的 readState 是 @Link（双向绑定），父组件必须提供真实的 @State 作为绑定源，
  // 不能用计算属性/getter，否则运行时报 "source variable in parent/ancestor must be defined"。
  @State readState: ReadStateCode = ReadStateCode.WAITING;
  // 全局朗读态经 AppStorage 广播；变化时重算本图标的 readState（仅活跃 id 命中自身时反映真实状态）
  @StorageProp('readerActiveId') @Watch('syncReadState') activeId: string = '';
  @StorageProp('readerState') @Watch('syncReadState') globalState: number = ReadStateCode.WAITING;
  @StorageProp('readerProgress') progress: number = 0;

  aboutToAppear(): void {
    this.syncReadState();
  }

  // 依据"当前活跃朗读 id + 全局状态"刷新本图标状态；非活跃图标恒为待播
  syncReadState(): void {
    this.readState = this.activeId === this.readId ? this.globalState as ReadStateCode : ReadStateCode.WAITING;
  }

  // 仅当本按钮对应的内容正在朗读时，才展示进度百分比
  private get isActive(): boolean {
    return this.activeId === this.readId;
  }

  build() {
    Row() {
      TextReaderIcon({ readState: this.readState })
        .width(24)
        .height(24)
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(FONT.bodySm)
          .fontColor($r('app.color.brand'))
          .margin({ left: SPACE.xs })
      }
      if (this.isActive) {
        Text(`${Math.max(0, Math.min(100, Math.round(this.progress)))}%`)
          .fontSize(FONT.mini)
          .fontColor($r('app.color.brand'))
          .margin({ left: SPACE.xs })
      }
    }
    .height(36)
    .padding({ left: SPACE.sm, right: this.label.length > 0 || this.isActive ? SPACE.md : SPACE.sm })
    .backgroundColor($r('app.color.tag_bg'))
    .borderRadius(RADIUS.pill)
    .flexShrink(0)
    .onClick(() => {
      SpeechReader.play(getContext(this) as common.Context, this.readId, this.title, this.text);
    })
  }
}
