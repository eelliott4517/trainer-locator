// Trainer Locator data scrape for Wowhead's WoW: Forever database.
//
// 1. Run the bridge that saves what the browser hands it:  python3 tools/recv.py
// 2. Open https://www.wowhead.com/forever/npcs?filter=28;1;0 (every NPC flagged as a trainer), open
//    the browser's developer console, paste this and press Enter.
// It loads each trainer's page (its map spots and its Teaches tabs) one at a time, at least 4 seconds
// apart (faster and Wowhead turns requests away for most of an hour), and waits 10 minutes whenever
// Wowhead turns one away anyway, so a full run takes an hour or more. A page that isn't there (404)
// counts as empty at once. Progress is in TS (TS.done of TS.total) and is kept in localStorage every
// 20 NPCs, so a reload picks up where it stopped (localStorage.removeItem("tl_scrape") starts afresh).
// When it's done the tab goes to the bridge, which writes tools/data/wowhead/scrape.json; then run
// python3 tools/build_data.py.
// Where the bridge can't be reached (Claude's built-in browser), run window.TL_NO_BRIDGE = true
// first: the finished scrape then stays in TS.packed (gzip, base64) for tools/import_scrape.py.
// Forever trainers Wowhead doesn't flag as trainers (found by probing its NPC tooltips) are in EXTRA:
// the list leaves them out, so their name and title come from their tooltips and their reactions from
// their pages, and build_data.py goes by their title when Wowhead has no Teaches tab for them either.
void (async () => {
	const BRIDGE = "http://127.0.0.1:18766/save?name=scrape.json#";
	const DELAY = 4000;
	const EXTRA = [
		270263, 270278,     // Aerie Peak's shaman and warrior trainers
		271465, 271478,     // Zephras Isle's artisan weapon crafter and armorsmith
		260080, 259287,     // Riverglades' weapons trainer and expert enchanter
	];
	// a timer in a Worker: a background tab (or a hidden browser pane) slows setTimeout to a crawl
	const sleep = ms => new Promise(r => {
		const w = new Worker(URL.createObjectURL(new Blob([`setTimeout(() => postMessage(0), ${ms})`], { type: "text/javascript" })));
		w.onmessage = () => { w.terminate(); r(); };
	});
	const pack = async obj => {
		const s = new Blob([JSON.stringify(obj)]).stream().pipeThrough(new CompressionStream("gzip"));
		const buf = new Uint8Array(await new Response(s).arrayBuffer());
		let bin = "";
		for (let i = 0; i < buf.length; i += 32768) bin += String.fromCharCode.apply(null, buf.subarray(i, i + 32768));
		return btoa(bin);
	};
	const unpack = async b => {
		const bin = atob(b), u = new Uint8Array(bin.length);
		for (let i = 0; i < bin.length; i++) u[i] = bin.charCodeAt(i);
		return JSON.parse(await new Response(new Blob([u]).stream().pipeThrough(new DecompressionStream("gzip"))).text());
	};
	const TS = (window.TS = { npcs: {}, done: 0, total: 0, blocked: 0 });

	// A page's text, at least DELAY after the last one; "" at once when it isn't there (404). Anything
	// else is Wowhead turning requests away: wait 10 minutes and try again.
	let last = 0;
	async function get(url) {
		for (;;) {
			const wait = last + DELAY + Math.random() * 1000 - Date.now();
			if (wait > 0) await sleep(wait);
			last = Date.now();
			let r = null;
			try { r = await fetch(url); } catch (e) { /* network hiccup */ }
			if (r && r.status === 200) return await r.text();
			if (r && r.status === 404) return "";
			TS.blocked++;
			await sleep(600000);
		}
	}
	// The JSON array starting at text[start]
	function arrayAt(text, start) {
		let depth = 0, quoted = false, escaped = false;
		for (let i = start; i < text.length; i++) {
			const c = text[i];
			if (quoted) {
				if (escaped) escaped = false;
				else if (c === "\\") escaped = true;
				else if (c === '"') quoted = false;
				continue;
			}
			if (c === '"') quoted = true;
			else if (c === "[") depth++;
			else if (c === "]" && --depth === 0) return JSON.parse(text.slice(start, i + 1));
		}
		return null;
	}
	// A page's Teaches tabs (teaches-ability, teaches-recipe, teaches-other), trimmed to the fields
	// build_data.py reads
	function teaches(text) {
		const out = {};
		for (const m of text.matchAll(/new Listview\(\{template: '(\w+)', id: '([\w-]+)'/g)) {
			if (!m[2].startsWith("teaches")) continue;
			const rows = arrayAt(text, text.indexOf("data: [", m.index) + 6) || [];
			out[m[2]] = rows.map(s => [s.id, s.name, s.level, s.skill, s.learnedat, s.trainingcost, s.chrclass, s.reqclass,
				s.cat, s.rank, s.reqrace, s.colors]);
		}
		return out;
	}
	// An EXTRA NPC's row as the trainer list would have it: name and title from its tooltip (the line
	// under the name, unless that's its type, "Level 5 Humanoid (Normal)"; nether.wowhead.com answers
	// any origin), and [Alliance, Horde] reactions from the React line of its page's Quick Facts
	// ([color=q2] friendly, [color=q10] hostile, others neutral; null when the page has none).
	// reactText keeps that line to check by. Without the tooltip the name comes from the page's title.
	const plain = html => new DOMParser().parseFromString(html, "text/html").documentElement.textContent.trim();
	async function extraRow(id, page) {
		const title = page.match(/<title>([^<]*?) - /);
		const row = { id, name: title ? plain(title[1]) : "NPC " + id, tag: null, react: [null, null] };
		await sleep(DELAY);
		let tip = null;
		try {
			const r = await fetch("https://nether.wowhead.com/forever/tooltip/npc/" + id);
			if (r.ok) tip = await r.json();
		} catch (e) { /* the page's title will do for the name */ }
		if (tip) {
			const lines = [...(tip.tooltip || "").matchAll(/<td>([\s\S]*?)<\/td>/g)].map(m => plain(m[1]));
			row.name = tip.name || lines[0] || row.name;
			if (lines[1] && !/^Level |\((Normal|Elite|Rare|Rare Elite|Boss)\)$/.test(lines[1])) row.tag = lines[1];
		} else {
			row.noTooltip = true;
		}
		const facts = page.match(/React:([\s\S]*?)\[\\?\/li\]/);
		if (facts) {
			row.reactText = facts[1].slice(0, 200);
			for (const m of facts[1].matchAll(/\[color=(\w*)\]([AH])/g)) {
				row.react[m[2] === "A" ? 0 : 1] = m[1] === "q2" ? 1 : m[1] === "q10" ? -1 : 0;
			}
		}
		return row;
	}

	const saved = localStorage.getItem("tl_scrape");
	if (saved) Object.assign(TS.npcs, (await unpack(saved)).npcs);
	const list = await get("/forever/npcs?filter=28;1;0");
	const TR = (window.TR = arrayAt(list, list.indexOf('"data":[', list.indexOf("new Listview")) + 7));
	const queue = TR.concat(EXTRA.filter(id => !TR.some(n => n.id === id)).map(id => ({ id, extra: true })));
	TS.total = queue.length;
	let fetched = 0;
	for (const n of queue) {
		if (!TS.npcs[n.id]) {
			const t = await get("/forever/npc=" + n.id);
			if (!t) {
				TS.npcs[n.id] = { list: n.extra ? { id: n.id, name: "NPC " + n.id } : n, missing: true };
			} else {
				const at = t.indexOf("g_mapperData = ");
				const map = at >= 0 ? JSON.parse(t.slice(at + 15, t.indexOf(";\n", at))) : null;
				TS.npcs[n.id] = n.extra ? { list: await extraRow(n.id, t), map, teach: teaches(t), extra: true }
					: { list: n, map, teach: teaches(t) };
			}
			if (++fetched % 20 === 0) localStorage.setItem("tl_scrape", await pack({ npcs: TS.npcs }));
		}
		TS.done++;
	}
	const all = await pack({ list: TR, npcs: TS.npcs, extra: EXTRA });
	localStorage.setItem("tl_scrape", all);
	TS.packed = all;
	TS.finished = true;
	if (!window.TL_NO_BRIDGE) location.href = BRIDGE + encodeURIComponent(all);
})();
"started";
