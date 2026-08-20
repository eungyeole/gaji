const repository = "https://github.com/eungyeole/rift";
const download = `${repository}/releases/download/nightly/Rift-macOS.dmg`;

function Mark() {
  return <svg viewBox="0 0 36 36" aria-hidden="true"><defs><linearGradient id="mark"><stop stopColor="#a093ff" /><stop offset="1" stopColor="#36bffa" /></linearGradient></defs><path fill="url(#mark)" d="M8 4h11.6C26.5 4 31 7.8 31 13.8c0 4-2.1 7-5.8 8.7L32 32h-8.2l-5.6-8.3h-3V32H8V4Zm7.2 6.1v7.7h4c2.9 0 4.5-1.4 4.5-3.9s-1.6-3.8-4.5-3.8h-4Z" /></svg>;
}

function Brand({ compact = false }) {
  return <a className="brand" href="#top" aria-label="Rift home">{!compact && <Mark />}<span>Rift</span></a>;
}

function Navigation() {
  return <header className="nav shell"><Brand /><nav aria-label="Primary"><a href="#experience">Experience</a><a href="#native">Why native</a><a href={repository}>GitHub</a></nav></header>;
}

function AppPreview() {
  const commits = [
    ["", "Polish repository inspector", "main · origin/main"],
    ["blue", "Cache file diff details", "e82a3d1"],
    ["violet", "Inspect stashed changes", "feature/inspector"],
    ["", "Refine loading feedback", "7fa21de"],
    ["", "Unify change rows", "24021e3"],
  ];

  return <div className="preview-stage"><div className="ambient-orb orb-one" /><div className="ambient-orb orb-two" /><div className="app-window" aria-label="Stylized preview of the Rift repository workspace">
    <div className="window-bar"><i /><i /><i /><span>rift</span></div>
    <div className="app-grid">
      <aside className="mock-sidebar"><small>LOCAL</small><b className="selected">●&nbsp; main</b><b>feature/inspector</b><small>REMOTE</small><b>origin/main</b><small>STASHES</small><b>WIP: diff polish</b></aside>
      <div className="mock-history">{commits.map(([kind, title, detail]) => <div className={`commit ${kind}`} key={title}><span /><p><b>{title}</b><small>{detail}</small></p></div>)}</div>
      <aside className="mock-inspector"><header><strong>Unstaged</strong><button>Stage all</button></header><p><i className="modified">M</i> apps/macos/ContentView.swift <b>+</b></p><p><i className="added">+</i> docs/index.html <b>+</b></p><header className="staged"><strong>Staged</strong><small>0</small></header><div className="composer"><strong>Commit</strong><span>Summary</span><button>Commit to main</button></div></aside>
    </div>
  </div></div>;
}

function Hero() {
  return <section className="hero shell"><p className="eyebrow"><i /> Made for macOS</p><h1>Git has never felt<br /><em>this at home.</em></h1><p className="lede">A beautifully native Git workspace shaped around the way your Mac looks, moves, and feels. Your history stays clear. Your focus stays yours.</p><div className="actions"><a className="button primary" href={download}>Download Rift</a><a className="button" href="#experience">See the experience</a></div><p className="availability">Nightly preview · macOS 26+ · Apple silicon and Intel</p><AppPreview /></section>;
}

function Experience() {
  return <section className="section shell" id="experience"><div className="heading centered"><p className="eyebrow">Clarity at every turn</p><h2>Your repository,<br />beautifully understood.</h2><p>Rift brings the whole story together without burying you in controls. See where you are, what changed, and what comes next.</p></div><div className="story-grid">
    <article className="story-card story-wide"><div><p className="story-kicker">History that reads naturally</p><h3>Follow every branch<br />without losing the plot.</h3><p>Compact lanes, clear refs, and familiar faces turn a complicated history into something you can scan at a glance.</p></div><div className="mini-graph" aria-hidden="true"><i /><i /><i /><i /><span>Ship the new inspector</span><span>Refine the diff experience</span><span>Bring changes together</span><span>Start with a clean foundation</span></div></article>
    <article className="story-card"><div className="glass-control"><span>Pull</span><b>⌄</b></div><div><p className="story-kicker">Less ceremony</p><h3>The right action,<br />right where you need it.</h3><p>Common Git flows feel direct. Advanced choices stay close without crowding the moment.</p></div></article>
    <article className="story-card"><div className="change-stack"><span><i className="modified">M</i> ContentView.swift <b>+</b></span><span><i className="added">+</i> Inspector.swift <b>+</b></span><span><i>−</i> LegacyView.swift <b>+</b></span></div><div><p className="story-kicker">Changes you can trust</p><h3>Review with confidence.</h3><p>Beautiful diffs and focused staging keep every commit intentional.</p></div></article>
  </div></section>;
}

function NativeStory() {
  return <section className="native-section" id="native"><div className="shell native-copy"><p className="eyebrow">Native by design</p><h2>Not a website<br />wearing a Mac costume.</h2><p>Rift is built with SwiftUI and AppKit, embracing Liquid Glass where it adds depth, system controls where familiarity matters, and native behavior everywhere else.</p><div className="native-points"><div><strong>Feels instantly familiar</strong><span>Windows, menus, shortcuts, materials, and interactions behave the way Mac users expect.</span></div><div><strong>Fast where it matters</strong><span>A shared Rust core keeps repository work responsive while the interface stays fluid.</span></div><div><strong>Quietly powerful</strong><span>Rebase, cherry-pick, conflict resolution, stashes, worktrees, and more—ready when you need them.</span></div></div></div></section>;
}

function Closing() {
  return <section className="closing shell"><p className="eyebrow">Meet your new Git workspace</p><h2>Stay in flow.<br />Ship with confidence.</h2><p>Download the latest preview and experience Git made for the Mac.</p><div className="actions"><a className="button primary" href={download}>Download for Mac</a><a className="button" href={repository}>View on GitHub</a></div><p className="windows-note">Windows release planned for a later stage.</p></section>;
}

export default function App() {
  return <><Navigation /><main id="top"><Hero /><Experience /><NativeStory /><Closing /></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}
