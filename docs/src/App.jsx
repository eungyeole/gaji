const repository = "https://github.com/eungyeole/rift";
const download = `${repository}/releases/download/nightly/Rift-macOS.dmg`;

const features = [
  ["Read the graph", "Follow compact commit lanes, refs, merge paths, and authors. Select a commit to inspect every changed file."],
  ["Shape a commit", "Review structured diffs, then stage or unstage whole files and individual hunks."],
  ["Move between work", "Search branches, switch with a double-click, manage worktrees, and restore repository tabs."],
  ["Recover context", "Browse stash contents before applying them. Inspect every saved file and its diff."],
  ["Handle real Git", "Pull, resolve conflicts, rebase, cherry-pick, revert, reset, and continue without losing context."],
  ["Keep your setup", "Your installed Git preserves credential helpers, SSH configuration, hooks, filters, and remotes."],
];

function Mark() {
  return <svg viewBox="0 0 36 36" aria-hidden="true"><defs><linearGradient id="mark"><stop stopColor="#a093ff" /><stop offset="1" stopColor="#36bffa" /></linearGradient></defs><path fill="url(#mark)" d="M8 4h11.6C26.5 4 31 7.8 31 13.8c0 4-2.1 7-5.8 8.7L32 32h-8.2l-5.6-8.3h-3V32H8V4Zm7.2 6.1v7.7h4c2.9 0 4.5-1.4 4.5-3.9s-1.6-3.8-4.5-3.8h-4Z" /></svg>;
}

function Brand({ compact = false }) {
  return <a className="brand" href="#top" aria-label="Rift home">{!compact && <Mark />}<span>Rift</span></a>;
}

function Navigation() {
  return <header className="nav shell"><Brand /><nav aria-label="Primary"><a href="#features">Features</a><a href="#architecture">Architecture</a><a href={repository}>GitHub</a></nav></header>;
}

function AppPreview() {
  const commits = [
    ["", "Polish repository inspector", "main · origin/main"],
    ["blue", "Cache file diff details", "e82a3d1"],
    ["violet", "Inspect stashed changes", "feature/inspector"],
    ["", "Refine loading feedback", "7fa21de"],
    ["", "Unify change rows", "24021e3"],
  ];

  return <div className="app-window" aria-label="Stylized preview of the Rift repository workspace">
    <div className="window-bar"><i /><i /><i /><span>rift</span></div>
    <div className="app-grid">
      <aside className="mock-sidebar"><small>LOCAL</small><b className="selected">●&nbsp; main</b><b>feature/inspector</b><small>REMOTE</small><b>origin/main</b><small>STASHES</small><b>WIP: diff polish</b></aside>
      <div className="mock-history">{commits.map(([kind, title, detail]) => <div className={`commit ${kind}`} key={title}><span /><p><b>{title}</b><small>{detail}</small></p></div>)}</div>
      <aside className="mock-inspector"><header><strong>Unstaged</strong><button>Stage all</button></header><p><i className="modified">M</i> apps/macos/ContentView.swift <b>+</b></p><p><i className="added">+</i> docs/index.html <b>+</b></p><header className="staged"><strong>Staged</strong><small>0</small></header><div className="composer"><strong>Commit</strong><span>Summary</span><button>Commit to main</button></div></aside>
    </div>
  </div>;
}

function Hero() {
  return <section className="hero shell"><p className="eyebrow"><i /> Native on macOS 26</p><h1>Your Git history,<br /><em>without the noise.</em></h1><p className="lede">Branches, commits, changes, stashes, and diffs in one calm, platform-native workspace—powered by Rust, shaped for the Mac.</p><div className="actions"><a className="button primary" href={download}>Download for Mac</a><a className="button" href={repository}>View on GitHub</a></div><p className="availability">Nightly preview · macOS 26+ · Apple silicon and Intel</p><AppPreview /></section>;
}

function Features() {
  return <section className="section shell" id="features"><div className="heading"><p className="eyebrow">A focused workspace</p><h2>Everything important stays close.</h2><p>No browser shell and no cross-platform imitation. Native controls and system materials keep the interface clear.</p></div><div className="feature-grid">{features.map(([title, copy], index) => <article key={title}><span>{String(index + 1).padStart(2, "0")}</span><h3>{title}</h3><p>{copy}</p></article>)}</div></section>;
}

function Architecture() {
  return <section className="section shell" id="architecture"><div className="heading"><p className="eyebrow">Shared behavior, native interfaces</p><h2>One engine. The right UI for each platform.</h2></div><div className="architecture"><div className="platform active"><small>CURRENT FOCUS</small><strong>SwiftUI + AppKit</strong><span>macOS 26</span></div><b>rift-ffi</b><div className="platform core"><small>SHARED ENGINE</small><strong>rift-core</strong><span>Rust · installed Git</span></div><b>rift-ffi</b><div className="platform"><small>PLANNED</small><strong>Windows</strong><span>Release coming later</span></div></div><p className="note">Rift is available for macOS today. A native Windows release is planned for a later stage.</p></section>;
}

function Build() {
  return <section className="section build shell" id="build"><div><p className="eyebrow">Build the current app</p><h2>Run Rift on a Mac.</h2><p>Requires macOS 26, Xcode 26 with Swift 6.2, stable Rust, and Git.</p></div><pre><code><span>$</span> git clone https://github.com/eungyeole/rift.git{"\n"}<span>$</span> cd rift{"\n"}<span>$</span> cargo build -p rift-ffi --release{"\n"}<span>$</span> swift run --package-path apps/macos RiftMac</code></pre></section>;
}

export default function App() {
  return <><Navigation /><main id="top"><Hero /><Features /><Architecture /><Build /><section className="closing shell"><p className="eyebrow">Still taking shape</p><h2>Build the Git client<br />you want to use.</h2><p>Rift is open source and under active development. Explore the code, report an issue, or help refine the native experience.</p><a className="button primary" href="#build">Build from source</a></section></main><footer className="shell"><Brand compact /><p>Native Git for macOS. Shared Rust core.</p><a href={repository}>GitHub</a></footer></>;
}
