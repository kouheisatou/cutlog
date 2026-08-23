// 見比べる画面の一覧。
// ★ web 側は「どこを押すとその画面に着くか」で書く。app.js は module なので、
//   中の関数は外から呼べない。押して辿るのがいちばん確かで、壊れにくい。
// ★ Flutter 側は同じ名前を URL の後ろに付けるだけで、同じ所へ着くようにしてある。

/** 端末の見立て。web も Flutter も、必ず同じ数字で撮る。 */
export const VIEWPORT = { width: 390, height: 844, scale: 3, mobile: true };

export const SCREENS = [
  {
    name: 'auth',
    title: 'ログイン',
    signedOut: true,          // 入る前の画面なので、鍵を持たずに開く
    steps: [{ wait: '#authScreen .auth-card' }],
  },
  {
    name: 'logs',
    title: 'ログ一覧',
    steps: [{ wait: '#logsScreen .log-row' }],
  },
  {
    name: 'logs-add',
    title: 'ログを追加（シート）',
    steps: [{ click: '#logsAddBtn' }, { wait: '#logAddDialog .panel' }],
  },
  {
    name: 'logs-search',
    title: 'ログを検索（シート）',
    steps: [{ click: '#logsSearchBtn' }, { wait: '#logSearchDialog .panel' }],
  },
  {
    name: 'log',
    title: 'ログ（カレンダー）',
    steps: [{ clickText: { sel: '#logsScreen .log-row', text: 'まいにち' } }, { wait: '#app .cal-day.has' }],
  },
  {
    name: 'logset',
    title: 'このログの設定',
    steps: [
      { clickText: { sel: '#logsScreen .log-row', text: 'まいにち' } }, { wait: '#app .cal-day.has' },
      { click: '#logSettingsBtn' }, { wait: '#logSetScreen .panel-row' },
    ],
  },
  {
    name: 'day',
    title: 'その日（つないだ再生）',
    steps: [
      { clickText: { sel: '#logsScreen .log-row', text: 'まいにち' } }, { wait: '#app .cal-day.has' },
      { click: '#app .cal-day.has' }, { wait: '#dayScreen .clip-row' },
    ],
  },
  {
    name: 'all',
    title: 'カット一覧',
    steps: [{ click: '.tab-item[data-tab="all"]' }, { wait: '#allScreen .photo-cell' }],
  },
  {
    name: 'all-search',
    title: '検索（シート）',
    steps: [
      { click: '.tab-item[data-tab="all"]' }, { wait: '#allScreen .photo-cell' },
      { click: '#allSearchBtn' }, { wait: '#searchDialog .panel' },
    ],
  },
  {
    name: 'cut',
    title: 'カットの詳細（シート）',
    steps: [
      { click: '.tab-item[data-tab="all"]' }, { wait: '#allScreen .photo-cell' },
      { click: '#allScreen .photo-cell' }, { wait: '#cutDialog .detail-head' },
      { waitMs: 700 },                       // 動画の1コマ目が出るまで待つ
    ],
  },
  {
    name: 'map',
    title: 'マップ',
    steps: [
      { click: '.tab-item[data-tab="map"]' },
      { wait: '#mapScreen .map-host' },
      { waitMs: 2500 },                      // 地図の瓦が届くまで待つ
    ],
  },
  {
    name: 'settings',
    title: '設定',
    steps: [{ click: '.tab-item[data-tab="settings"]' }, { wait: '#settingsScreen .panel-row' }],
  },
  {
    name: 'capture',
    title: '撮影',
    steps: [
      { click: '.tab-item[data-tab="camera"]' },
      { wait: '#captureDialog .capture' },
      { waitMs: 1200 },                      // 作り物のカメラの映像が出るまで待つ
    ],
  },
];

export const byName = (name) => SCREENS.find((s) => s.name === name);
