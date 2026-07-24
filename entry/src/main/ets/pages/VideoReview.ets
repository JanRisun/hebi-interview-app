// 视频录制回看页：VideoAnswer 录制完成后跳转
// 功能：播放器进度拖动、播放/暂停、重录（返回 VideoAnswer）、下一步（返回 Detail）
// 资源配色：app.color.danger / app.color.text_primary / app.color.surface
import { promptAction } from '@kit.ArkUI';
import display from '@ohos.display';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FONT, SPACE, SAFE_AREA_TYPES, SAFE_AREA_EDGES } from '../utils/Theme';

const DOMAIN: number = 0x0001;
const TAG: string = 'VideoReview';
const DANGER: string = '#EF4444';

interface VideoReviewParam { videoPath: string }

@Component
export struct VideoReviewView {
  @Prop params: Object;
  @StorageProp('safeTop') safeTop: number = 0;
  @StorageProp('safeBottom') safeBottom: number = 0;
  @Consume pageStack: NavPathStack;

  @State currentSec: number = 0;
  @State durationSec: number = 0;
  @State playing: boolean = false;
  @State completed: boolean = false;
  @State prepared: boolean = false;

  private videoController: VideoController = new VideoController();
  private videoPath: string = '';
  // 屏幕尺寸（px），用于把视频宽高对调后旋转居中铺满
  private screenW: number = 0;
  private screenH: number = 0;
  // 进度条拖动期间抑制 onUpdate 频繁推送，松开后再同步
  private seeking: boolean = false;

  aboutToAppear(): void {
    // 读取屏幕宽高（竖屏下 width < height）。注意 Display 返回的是 px，
    // 而布局 .width(number) 用的是 vp，需要除以 densityPixels 换算，否则视频会被放大数倍（只显示左上角）。
    try {
      const d = display.getDefaultDisplaySync();
      const density: number = (d.densityPixels && d.densityPixels > 0) ? d.densityPixels : 1;
      this.screenW = d.width / density;
      this.screenH = d.height / density;
    } catch (e) { /* ignore */ }
    const p = (this.params ?? {}) as Record<string, Object>;
    let vp: string = (p['videoPath'] as string) ?? '';
    // Video 组件加载应用沙箱文件必须用 file:// 前缀，否则 onPrepared 不触发（时长不显示、无法播放）
    if (vp.length > 0 && !vp.startsWith('file://')) {
      vp = 'file://' + vp;
    }
    this.videoPath = vp;
    if (!vp) {
      promptAction.showToast({ message: '视频文件缺失', duration: 1500 });
    }
  }

  aboutToDisappear(): void {
    try {
      this.videoController.stop();
    } catch (e) { /* ignore */ }
  }

  // 把秒数格式化为 mm:ss
  private fmt(sec: number): string {
    const total: number = Math.max(0, Math.floor(sec));
    const m: number = Math.floor(total / 60);
    const s: number = total % 60;
    const mm: string = m < 10 ? '0' + m : '' + m;
    const ss: string = s < 10 ? '0' + s : '' + s;
    return mm + ':' + ss;
  }

  private togglePlay(): void {
    try {
      if (!this.prepared) {
        return;
      }
      if (this.playing) {
        this.videoController.pause();
        this.playing = false;
      } else {
        if (this.completed) {
          // 已经播完：从头开始
          this.videoController.setCurrentTime(0);
          this.currentSec = 0;
          this.completed = false;
        }
        this.videoController.start();
        this.playing = true;
      }
    } catch (e) {
      const err = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'togglePlay fail: %{public}s', err.message);
    }
  }

  private reRecord(): void {
    try {
      this.videoController.stop();
    } catch (e) { /* ignore */ }
    // 通知 VideoAnswer 复位相机与录制状态后再返回（确保可重新录制）
    AppStorage.set('vaReset', ((AppStorage.get('vaReset') as number) || 0) + 1);
    // 回退到 VideoAnswer 重新录制
    this.pageStack.pop();
  }

  private goNext(): void {
    try {
      this.videoController.stop();
    } catch (e) { /* ignore */ }
    // 通知 VideoAnswer 复位（即便走两步返回 Detail，也保证实例可再次录制）
    AppStorage.set('vaReset', ((AppStorage.get('vaReset') as number) || 0) + 1);
    // 走完两道栈回到 Detail 页面（先退掉本页面，再退掉 VideoAnswer）
    this.pageStack.pop();
    this.pageStack.pop();
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // 黑色底色，避免视频区域之外露出白底
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(Color.Black)

      // 视频播放器：横屏录制的视频在竖屏下需逆时针旋转 90° 才能正向显示。
      // 用居中 Stack 承载，宽高对调（屏幕 vp）后 rotate(-90) + Cover 铺满；居中由 Stack 完成，避免手动 position 误差。
      // 点击区域放在承载容器上，旋转后命中区域更稳定。
      Stack({ alignContent: Alignment.Center }) {
        Video({
          src: this.videoPath,
          controller: this.videoController
        })
          .width(this.screenH)
          .height(this.screenW)
          .objectFit(ImageFit.Cover)
          .rotate({ angle: -90 })
          .scale({ y: -1 })
          .controls(false)
          .autoPlay(false)
        .onPrepared((event: PreparedInfo): void => {
          this.durationSec = event.duration;
          this.prepared = true;
          // 进入页面即自动播放录制好的视频
          try {
            this.videoController.start();
            this.playing = true;
          } catch (e) { /* ignore */ }
        })
          .onUpdate((event: PlaybackInfo): void => {
            if (!this.seeking) {
              this.currentSec = event.time;
            }
          })
          .onFinish((): void => {
            this.playing = false;
            this.completed = true;
            this.currentSec = this.durationSec;
          })
      }
      .width('100%')
      .height('100%')
      .onClick(() => {
        this.togglePlay();
      })

      // 居中播放控制：暂停/未开始显示播放按钮，播完显示重播按钮（点击可播放/重播）
      if (!this.playing || this.completed) {
        Stack({ alignContent: Alignment.Center }) {
          Column() {
            if (this.completed) {
              // 重播：白色环形箭头
              Text('\u21BB')
                .fontSize(36)
                .fontColor(Color.White)
            } else {
              // 播放：白色实心三角形，使用系统 SymbolGlyph（与录音页三角形同一渲染方式，居中稳定）
              SymbolGlyph($r('sys.symbol.play_fill'))
                .fontSize(40)
                .fontColor([Color.White])
            }
          }
          .width(80)
          .height(80)
          .borderRadius(40)
          .backgroundColor('rgba(0,0,0,0.5)')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
        }
        .width('100%')
        .height('100%')
        .onClick(() => {
          if (this.completed) {
            // 重播：回到开头重新播放
            try {
              this.videoController.setCurrentTime(0);
            } catch (e) { /* ignore */ }
            this.currentSec = 0;
            this.completed = false;
            this.videoController.start();
            this.playing = true;
          } else {
            this.togglePlay();
          }
        })
      }

      // 顶部关闭按钮
      Row() {
        SymbolGlyph($r('sys.symbol.xmark'))
          .fontSize(22)
          .fontColor([Color.White])
          .padding(8)
          .onClick(() => {
            // 通知 VideoAnswer 复位相机与录制状态后再返回（确保可重新录制）
            AppStorage.set('vaReset', ((AppStorage.get('vaReset') as number) || 0) + 1);
            this.pageStack.pop();
          })
      }
      .width('100%')
      .padding({ left: SPACE.lg, top: this.safeTop + SPACE.sm })
      .position({ x: 0, y: 0 })

      // 底部控制条：时间 + 进度条 + 重录/下一步（仅内容高度、靠底部，避免遮挡视频点击）
      Column() {
          // 进度条行
          Row() {
            Text(this.fmt(this.currentSec))
              .fontSize(13)
              .fontColor(Color.White)
              .width(52)
              .textAlign(TextAlign.Start)
            Slider({
              value: this.currentSec,
              min: 0,
              max: Math.max(1, this.durationSec),
              step: 1,
              style: SliderStyle.OutSet
            })
              .layoutWeight(1)
              .blockColor(DANGER)
              .trackColor('rgba(255,255,255,0.35)')
              .selectedColor(DANGER)
              .showSteps(false)
              .showTips(false)
              .onChange((value: number, mode: SliderChangeMode): void => {
                if (mode === SliderChangeMode.Begin) {
                  this.seeking = true;
                } else if (mode === SliderChangeMode.End) {
                  this.seeking = false;
                  this.currentSec = value;
                  try {
                    this.videoController.setCurrentTime(value);
                  } catch (e) { /* ignore */ }
                }
              })
            Text(this.fmt(this.durationSec))
              .fontSize(13)
              .fontColor(Color.White)
              .width(52)
              .textAlign(TextAlign.End)
          }
          .width('100%')
          .padding({ left: SPACE.lg, right: SPACE.lg, top: SPACE.sm, bottom: SPACE.md })

          // 重录 / 下一步 按钮
          Row() {
            Button('重录')
              .layoutWeight(1)
              .height(44)
              .backgroundColor('rgba(255,255,255,0.85)')
              .fontColor($r('app.color.text_primary'))
              .fontSize(FONT.body)
              .borderRadius(22)
              .onClick(() => {
                this.reRecord();
              })
            Blank().width(SPACE.md)
            Button('下一步')
              .layoutWeight(1)
              .height(44)
              .backgroundColor($r('app.color.danger'))
              .fontColor(Color.White)
              .fontSize(FONT.body)
              .borderRadius(22)
              .onClick(() => {
                this.goNext();
              })
          }
          .width('100%')
          .padding({ left: SPACE.lg, right: SPACE.lg, bottom: SPACE.lg + this.safeBottom })
        }
        .width('100%')
        .backgroundColor('rgba(0,0,0,0.65)')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea(SAFE_AREA_TYPES, SAFE_AREA_EDGES)
  }
}
