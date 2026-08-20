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
  return <header className="nav-shell"><div className="nav shell"><Brand /><nav aria-label="Primary"><a href={downloadPage}>Download</a><a href={repository}>GitHub</a></nav></div></header>;
}

function AppPreview() {
  return <div className="preview-stage"><div className="ambient-orb orb-one" /><div className="ambient-orb orb-two" /><figure className="product-shot"><img src={`${import.meta.env.BASE_URL}rift-workspace.png`} alt="Rift showing branches, commit history, and changed files in a native macOS window" /></figure></div>;
}

function Hero() {
  return <section className="hero shell"><p className="eyebrow"><i /> Native for macOS</p><h1>Git, at home<br /><em>on your Mac.</em></h1><p className="lede">History, changes, and branches in one focused window.</p><div className="actions"><a className="button primary" href={downloadPage}>Download</a></div><p className="availability">macOS 26+ · Apple silicon and Intel</p><AppPreview /></section>;
}

function Builders() {
  const row = (items, reverse) => <div className="builder-row"><div className={`builder-track${reverse ? " reverse" : ""}`}>{[0, 1, 2, 3, 4].map((copy) => <div className="builder-set" aria-hidden={copy > 0 || undefined} key={copy}>{items.map((name, index) => <span key={`${name}-${index}`}><img src={companies[name]} alt={name} /></span>)}</div>)}</div></div>;
  return <section className="builders" aria-labelledby="builders-title"><p id="builders-title">Trusted by shareholders of</p><div className="builder-marquee">{row(builders[0], false)}{row(builders[1], true)}</div><small>One share still makes you an owner. Technically.</small></section>;
}

function Experience() {
  return <section className="section shell" id="experience"><div className="heading"><p className="eyebrow">Rift</p><h2>Everything in its place.</h2></div><div className="story-grid">
    <article className="story-card story-wide"><div><p className="story-kicker">History</p><h3>A clear graph.<br />Nothing else.</h3></div><div className="mini-graph" aria-hidden="true"><i /><i /><i /><i /><span>Ship the new inspector</span><span>Refine the diff experience</span><span>Bring changes together</span><span>Start with a clean foundation</span></div></article>
    <article className="story-card"><div className="change-stack"><span><i className="modified">M</i> ContentView.swift <b>+</b></span><span><i className="added">+</i> Inspector.swift <b>+</b></span><span><i>−</i> LegacyView.swift <b>+</b></span></div><div><p className="story-kicker">Changes</p><h3>Review.<br />Stage. Commit.</h3></div></article>
    <article className="story-card"><div className="workflow-list"><span>Rebase</span><span>Cherry-pick</span><span>Conflicts</span><span>Worktrees</span><span>Stashes</span><span>Submodules</span></div><div><p className="story-kicker">More</p><h3>There when<br />you need it.</h3></div></article>
  </div></section>;
}

function NativeStory() {
  return <section className="native-section" id="native"><div className="shell native-copy"><p className="eyebrow">Built for Mac</p><h2>Native throughout.</h2><p>SwiftUI, AppKit, and Liquid Glass. Rift looks and behaves like it belongs.</p></div></section>;
}

function DownloadPage() {
  return <><Navigation /><main className="download-page"><section className="download-hero shell"><p className="eyebrow">Rift</p><h1>Download.</h1></section><section className="platform-downloads shell"><article><header><span>Available</span><strong>macOS</strong></header><p>macOS 26+ · Apple silicon and Intel</p><a className="button primary" href={macDownload}>Download DMG</a></article><article className="planned"><header><span>Planned</span><strong>Windows</strong></header><button className="button" disabled>Coming later</button></article></section><p className="install-note shell">Unsigned preview: open from Finder’s context menu the first time.</p></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}

export default function App() {
  if (window.location.pathname.endsWith("/download/") || window.location.pathname.endsWith("/download/index.html")) return <DownloadPage />;
  return <><Navigation /><main id="top"><Hero /><Builders /><Experience /><NativeStory /></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}
