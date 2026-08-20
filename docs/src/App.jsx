const repository = "https://github.com/eungyeole/rift";
const download = `${repository}/releases/download/nightly/Rift-macOS.dmg`;
const builders = ["Your team", "Studio", "Open source", "Product", "Platform", "Independent"];

function Mark() {
  return <svg viewBox="0 0 36 36" aria-hidden="true"><defs><linearGradient id="mark" x1="7" y1="5" x2="29" y2="31" gradientUnits="userSpaceOnUse"><stop stopColor="#76dcff" /><stop offset=".52" stopColor="#0a84ff" /><stop offset="1" stopColor="#a77bff" /></linearGradient></defs><path d="M9 30V6h9.5C24 6 27 8.8 27 13.4s-3 7.5-8.5 7.5H9" fill="none" stroke="url(#mark)" strokeWidth="3.4" strokeLinecap="round" strokeLinejoin="round" /><path d="m18.5 20.9 9 9.1" fill="none" stroke="url(#mark)" strokeWidth="3.4" strokeLinecap="round" /><circle cx="9" cy="6" r="2" fill="#76dcff" /><circle cx="9" cy="30" r="2" fill="#0a84ff" /><circle cx="27.5" cy="30" r="2" fill="#a77bff" /></svg>;
}

function Brand({ compact = false }) {
  return <a className="brand" href="#top" aria-label="Rift home">{!compact && <Mark />}<span>Rift</span></a>;
}

function Navigation() {
  return <header className="nav shell"><Brand /><nav aria-label="Primary"><a href="#experience">Experience</a><a href="#native">Why native</a><a href={repository}>GitHub</a></nav></header>;
}

function AppPreview() {
  return <div className="preview-stage"><div className="ambient-orb orb-one" /><div className="ambient-orb orb-two" /><figure className="product-shot"><img src={`${import.meta.env.BASE_URL}rift-workspace.png`} alt="Rift showing branches, commit history, and changed files in a native macOS window" /></figure></div>;
}

function Hero() {
  return <section className="hero shell"><p className="eyebrow"><i /> Native for macOS 26</p><h1>A native Git client<br /><em>for your Mac.</em></h1><p className="lede">History, branches, changes, stashes, and diffs in one focused window—built with SwiftUI, AppKit, and Liquid Glass.</p><div className="actions"><a className="button primary" href={download}>Download for Mac</a><a className="button" href={repository}>View source</a></div><p className="availability">Nightly preview · Apple silicon and Intel · Unsigned build</p><AppPreview /><div className="trust-strip"><span><strong>48 core Git operations</strong>Implemented in the shared engine today.</span><span><strong>No account required</strong>Open a repository and start working.</span><span><strong>Open source</strong>Inspect the code and follow every change.</span></div></section>;
}

function Builders() {
  const logos = <div className="builder-set">{builders.map((builder, index) => <span key={builder}><i>{String(index + 1).padStart(2, "0")}</i>{builder}</span>)}</div>;
  return <section className="builders" aria-labelledby="builders-title"><p id="builders-title">Used by builders from</p><div className="builder-marquee"><div className="builder-track">{logos}<div className="builder-set" aria-hidden="true">{builders.map((builder, index) => <span key={builder}><i>{String(index + 1).padStart(2, "0")}</i>{builder}</span>)}</div></div></div><small>Community slots · replace with verified teams as Rift grows</small></section>;
}

function Experience() {
  return <section className="section shell" id="experience"><div className="heading"><p className="eyebrow">Inside Rift</p><h2>Built around real Git work.</h2><p>The interface keeps navigation, history, diffs, and the working copy connected without turning the window into a control panel.</p></div><div className="story-grid">
    <article className="story-card story-wide"><div><p className="story-kicker">History</p><h3>A compact graph,<br />with room for the work.</h3><p>Branches, refs, authors, and changed files remain readable even when the history gets busy.</p></div><div className="mini-graph" aria-hidden="true"><i /><i /><i /><i /><span>Ship the new inspector</span><span>Refine the diff experience</span><span>Bring changes together</span><span>Start with a clean foundation</span></div></article>
    <article className="story-card"><div className="change-stack"><span><i className="modified">M</i> ContentView.swift <b>+</b></span><span><i className="added">+</i> Inspector.swift <b>+</b></span><span><i>−</i> LegacyView.swift <b>+</b></span></div><div><p className="story-kicker">Working copy</p><h3>Review, stage,<br />and commit.</h3><p>Files and hunks move through one consistent inspector, with structured diffs in the center.</p></div></article>
    <article className="story-card"><div className="workflow-list"><span>Rebase</span><span>Cherry-pick</span><span>Resolve conflicts</span><span>Worktrees</span><span>Stashes</span><span>Submodules</span></div><div><p className="story-kicker">Workflows</p><h3>The full toolset,<br />kept out of the way.</h3><p>Common actions stay immediate. The rest is available without competing for attention.</p></div></article>
  </div></section>;
}

function NativeStory() {
  return <section className="native-section" id="native"><div className="shell native-copy"><p className="eyebrow">Built for Mac</p><h2>Native throughout.</h2><p>SwiftUI and AppKit provide the window, menus, keyboard behavior, system materials, and Liquid Glass. The interface follows macOS instead of recreating it.</p><div className="native-points"><div><strong>System UI</strong><span>Familiar controls, shortcuts, focus, accessibility, and window behavior.</span></div><div><strong>Liquid Glass</strong><span>Used for navigation and controls where depth communicates hierarchy.</span></div><div><strong>Rust core</strong><span>Repository operations shared across the project without sharing the interface.</span></div></div></div></section>;
}

function Closing() {
  return <section className="closing shell"><p className="eyebrow">Rift for macOS</p><h2>Try the current preview.</h2><p>Rift is under active development. Download the nightly build or follow the project on GitHub.</p><div className="actions"><a className="button primary" href={download}>Download for Mac</a><a className="button" href={repository}>View on GitHub</a></div><p className="windows-note">Windows release planned for a later stage.</p></section>;
}

export default function App() {
  return <><Navigation /><main id="top"><Hero /><Builders /><Experience /><NativeStory /><Closing /></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}
