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
  return <section className="hero shell"><h1>Native throughout.</h1><p className="lede">Liquid Glass. Light by design. Fast by nature.</p><div className="actions"><a className="button primary" href={downloadPage}>Download</a></div><p className="availability">macOS 26+ · Apple silicon and Intel</p><AppPreview /></section>;
}

function Builders() {
  const row = (items, reverse) => <div className="builder-row"><div className={`builder-track${reverse ? " reverse" : ""}`}>{[0, 1, 2, 3, 4].map((copy) => <div className="builder-set" aria-hidden={copy > 0 || undefined} key={copy}>{items.map((name, index) => <span key={`${name}-${index}`}><img src={companies[name]} alt={name} /></span>)}</div>)}</div></div>;
  return <section className="builders" aria-labelledby="builders-title"><p id="builders-title">Trusted by shareholders of</p><div className="builder-marquee">{row(builders[0], false)}{row(builders[1], true)}</div><small>One share still makes you an owner. Technically.</small></section>;
}

function Experience() {
  return <section className="section shell" id="experience"><div className="heading"><p className="eyebrow">Why Rift</p><h2>Everything in its place.</h2><p>Rift uses the Mac’s own interface instead of carrying a browser with it.</p></div><div className="story-grid">
    <article className="story-card"><p className="story-kicker">Native UI</p><h3>Made of macOS.</h3><p>System controls, menus, shortcuts, and window behavior feel familiar from the first click.</p></article>
    <article className="story-card"><p className="story-kicker">Liquid Glass</p><h3>Part of the system.</h3><p>Native materials bring depth where it helps, without adding another visual language.</p></article>
    <article className="story-card"><p className="story-kicker">Light &amp; fast</p><h3>Less between you and Git.</h3><p>No embedded browser. Less overhead. A compact app backed by a fast Rust core.</p></article>
  </div></section>;
}

function DownloadPage() {
  return <><Navigation /><main className="download-page"><section className="download-hero shell"><p className="eyebrow">Rift</p><h1>Download.</h1></section><section className="platform-downloads shell"><article><header><span>Available</span><strong>macOS</strong></header><p>macOS 26+ · Apple silicon and Intel</p><a className="button primary" href={macDownload}>Download DMG</a></article><article className="planned"><header><span>Planned</span><strong>Windows</strong></header><button className="button" disabled>Coming later</button></article></section><p className="install-note shell">Unsigned preview: open from Finder’s context menu the first time.</p></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}

export default function App() {
  if (window.location.pathname.endsWith("/download/") || window.location.pathname.endsWith("/download/index.html")) return <DownloadPage />;
  return <><Navigation /><main id="top"><Hero /><Builders /><Experience /></main><footer className="shell"><Brand compact /><p>Native Git for macOS.</p><a href={repository}>GitHub</a></footer></>;
}
