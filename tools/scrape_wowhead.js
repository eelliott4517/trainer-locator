// Trainer Locator data scrape for Wowhead's WoW: Forever database.
//
// 1. Run the bridge that saves what the browser hands it:  python3 tools/recv.py
// 2. Open https://www.wowhead.com/forever/npcs?filter=28;1;0 (every NPC flagged as a trainer), open
//    the browser's developer console, paste this and press Enter.
// It loads each trainer's page (its map spots and its Teaches tabs), two at a time with a second
// between, and waits 30 seconds whenever Wowhead turns a request away, so a full run takes an hour
// or more. Progress is in TS (TS.done of TR.length) and is kept in localStorage every 20 NPCs, so a
// reload picks up where it stopped. When it's done the tab goes to the bridge, which writes
// tools/data/wowhead/scrape.json; then run python3 tools/build_data.py.
(async () => {
	const BRIDGE = "http://127.0.0.1:18766/save?name=scrape.json#";
	const sleep = ms => new Promise(r => setTimeout(r, ms));
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

	const list = await (await fetch("/forever/npcs?filter=28;1;0")).text();
	window.TR = arrayAt(list, list.indexOf('"data":[', list.indexOf("new Listview")) + 7);
	const TS = (window.TS = { npcs: {}, done: 0, blocked: 0 });
	const saved = localStorage.getItem("tl_scrape");
	if (saved) Object.assign(TS.npcs, (await unpack(saved)).npcs);

	async function one(n) {
		for (;;) {
			let r = null;
			try { r = await fetch("/forever/npc=" + n.id); } catch (e) { /* network hiccup */ }
			if (r && r.status === 200) {
				const t = await r.text();
				const at = t.indexOf("g_mapperData = ");
				let map = null;
				if (at >= 0) map = JSON.parse(t.slice(at + 15, t.indexOf(";\n", at)));
				TS.npcs[n.id] = { list: n, map, teach: teaches(t) };
				return;
			}
			if (r && r.status === 404) { TS.npcs[n.id] = { list: n, missing: true }; return; }
			TS.blocked++;
			await sleep(30000);
		}
	}
	const queue = TR.filter(n => !TS.npcs[n.id]);
	async function worker() {
		while (queue.length) {
			await one(queue.shift());
			if (++TS.done % 20 === 0) localStorage.setItem("tl_scrape", await pack({ npcs: TS.npcs }));
			await sleep(1000);
		}
	}
	await Promise.all([worker(), worker()]);
	const all = await pack({ list: TR, npcs: TS.npcs });
	localStorage.setItem("tl_scrape", all);
	TS.finished = true;
	location.href = BRIDGE + encodeURIComponent(all);
})();
