const repository = "https://github.com/eungyeole/rift";
const macDownload = `${repository}/releases/download/nightly/Rift-macOS.dmg`;
const home = import.meta.env.BASE_URL;
const downloadPage = `${home}download/`;
const companies = {
  Google: "https://cdn.jsdelivr.net/gh/devicons/devicon@latest/icons/google/google-plain-wordmark.svg",
  Samsung: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/samsung/mono.svg",
  Apple: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/apple/mono.svg",
  Tesla: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/tesla/wordmark.svg",
  Netflix: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/netflix/mono.svg",
  LG: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/lg/mono.svg",
  SpaceX: "https://cdn.jsdelivr.net/gh/glincker/thesvg@main/public/icons/spacex/mono.svg",
};
const builders = [["Google", "Samsung", "Apple", "Tesla", "Netflix", "LG", "SpaceX"], ["SpaceX", "LG", "Netflix", "Tesla", "Apple", "Samsung", "Google"]];

function Mark() {
  return <svg viewBox="0 0 36 36" aria-hidden="true"><defs><linearGradient id="rift-left" x1="5" y1="5" x2="17" y2="31" gradientUnits="userSpaceOnUse"><stop stopColor="#f5f5f7" /><stop offset="1" stopColor="#a1a1aa" /></linearGradient><linearGradient id="rift-right" x1="19" y1="5" x2="31" y2="31" gradientUnits="userSpaceOnUse"><stop stopColor="#c7c7cc" /><stop offset="1" stopColor="#636366" /></linearGradient></defs><path d="M5 5h12l-3.5 7 3.5 6-5 6 3 7H5V5Z" fill="url(#rift-left)" /><path d="M31 5H19l3.5 7-3.5 6 5 6-3 7h10V5Z" fill="url(#rift-right)" /></svg>;
}

function Brand({ compact = false }) {
  return <a className="brand" href={home} aria-label="Rift home">{!compact && <Mark />}<span>Rift</span></a>;
}

function Navigation() {
  return <header className="nav-shell"><div className="nav shell"><Brand /><nav aria-label="Primary"><a href={`${home}#experience`}>Experience</a><a href={`${home}#native`}>Why native</a><a href={downloadPage}>Download</a><a href={repository}>GitHub</a></nav></div></header>;
}

function AppPreview() {
  return <div className="preview-stage"><div className="ambient-orb orb-one" /><div className="ambient-orb orb-two" /><figure className="product-shot"><img src={`${import.meta.env.BASE_URL}rift-workspace.png`} alt="Rift showing branches, commit history, and changed files in a native macOS window" /></figure></div>;
}

function Hero() {
  return <section className="hero shell"><p className="eyebrow"><i /> Native for macOS 26</p><h1>A native Git client<br /><em>for your Mac.</em></h1><p className="lede">History, branches, changes, stashes, and diffs in one focused window—built with SwiftUI, AppKit, and Liquid Glass.</p><div className="actions"><a className="button primary" href={downloadPage}>Download</a><a className="button" href={repository}>View source</a></div><p className="availability">Nightly preview · Apple silicon and Intel · Unsigned build</p><AppPreview /></section>;
}

function Builders() {
  const row = (items, reverse) => <div className="builder-row"><div className={`builder-track${reverse ? " reverse" : ""}`}>{[0, 1, 2, 3, 4].map((copy) => <div className="builder-set" aria-hidden={copy > 0 || undefined} key={copy}>{items.map((name, index) => <span key={`${name}-${index}`}><img src={companies[name]} alt={name} /></span>)}</div>)}</div></div>;
  return <section className="builders" aria-labelledby="builders-title"><p id="builders-title">Trusted by shareholders of</p><div className="builder-marquee">{row(builders[0], false)}{row(builders[1], true)}</div><small>One share still makes you an owner. Technically.</small></section>;
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
  return <section className="closing shell"><p className="eyebrow">Rift preview</p><h2>Try the current build.</h2><p>Rift is under active development. Download the nightly build or follow the project on GitHub.</p><div className="actions"><a className="button primary" href={downloadPage}>Download</a><a className="button" href={repository}>View on GitHub</a></div></section>;
}

function DownloadPage() {
  return <><Navigation /><main className="download-page"><section className="download-hero shell"><p className="eyebrow">Download Rift</p><h1>Choose your platform.</h1><p>Rift is currently available as a nightly preview.</p></section><section className="platform-downloads shell"><article><header><span>Available now</span><strong>macOS</strong></header><p>Universal build for Apple silicon and Intel.</p><dl><div><dt>Requires</dt><dd>macOS 26+</dd></div><div><dt>Format</dt><dd>DMG · unsigned preview</dd></div></dl><a className="button primary" href={macDownload}>Download DMG</a></article><article className="planned"><header><span>Planned</span><strong>Windows</strong></header><p>A native Windows release is planned for a later stage.</p><dl><div><dt>Status</dt><dd>In development</dd></div><div><dt>Availability</dt><dd>To be announced</dd></div></dl><button className="button" disabled>Coming later</button></article></section><p className="install-note shell">Because the current macOS preview is not notarized, open Rift from Finder’s context menu the first time.</p></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}

export default function App() {
  if (window.location.pathname.endsWith("/download/") || window.location.pathname.endsWith("/download/index.html")) return <DownloadPage />;
  return <><Navigation /><main id="top"><Hero /><Builders /><Experience /><NativeStory /><Closing /></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}
