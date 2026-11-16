// Interactive demo console shared by the landing page and the use case pages.
// Runs come from <script type="application/json" id="runs-data">; with a single
// run the run list is hidden. All text is inserted with textContent.
(function () {
  var data = document.getElementById('runs-data');
  var consoleEl = document.getElementById('console');
  if (!data || !consoleEl) return;
  var RUNS = JSON.parse(data.textContent);
  if (!RUNS.length) return;

  var TAGS = { fact: ['FACT', 'fact'], inf: ['INFERENCE', 'inf'] };
  var $ = function (id) { return document.getElementById(id); };
  var runsEl = $('runs'), timeline = $('timeline'), approve = $('approve'), reject = $('reject'), replay = $('replay');
  var current = 0;

  if (RUNS.length === 1) consoleEl.classList.add('single');

  // Renders `code` spans without innerHTML.
  function rich(el, text) {
    el.textContent = '';
    text.split('`').forEach(function (part, i) {
      if (!part) return;
      if (i % 2) { var c = document.createElement('code'); c.textContent = part; el.appendChild(c); }
      else el.appendChild(document.createTextNode(part));
    });
    return el;
  }
  function icon(href) {
    var ns = 'http://www.w3.org/2000/svg';
    var svg = document.createElementNS(ns, 'svg'); svg.setAttribute('class', 'ico');
    var use = document.createElementNS(ns, 'use'); use.setAttribute('href', href);
    svg.appendChild(use);
    return svg;
  }
  function step(cls, href, text, meta, added) {
    var li = document.createElement('li');
    if (added) li.className = 'added';
    var dot = document.createElement('span'); dot.className = 'dot ' + cls; dot.appendChild(icon(href));
    var m = document.createElement('span'); m.className = 'meta'; m.textContent = meta;
    li.append(dot, rich(document.createElement('span'), text), m);
    timeline.appendChild(li);
    return li;
  }
  function setState(cls, label) { $('state').className = 'state ' + cls; $('state').textContent = label; }

  function render(i) {
    current = i;
    var r = RUNS[i];
    if (runsEl) runsEl.querySelectorAll('button').forEach(function (b, j) { b.setAttribute('aria-pressed', String(i === j)); b.classList.toggle('active', i === j); });
    $('agent-name').textContent = r.agent;
    $('ask').textContent = r.ask;
    timeline.textContent = '';
    r.steps.forEach(function (s) { step('ok', '#i-check', s[0], s[1]); });
    step('wait', '#i-wait', 'Proposal is waiting for a human decision', 'you').id = 'gate';
    $('p-title').textContent = r.title;
    var diff = $('diff'); diff.textContent = '';
    r.diff.forEach(function (d) { var s = document.createElement('span'); s.className = d[0] === '+' ? 'add' : 'del'; s.textContent = d[0] + ' ' + d[1]; diff.appendChild(s); });
    $('note').textContent = 'The agent never applies changes itself';
    $('stat-label').textContent = r.stat[0]; $('stat-src').textContent = r.stat[1]; $('stat-value').textContent = r.stat[2];
    var ev = $('evidence'); ev.textContent = '';
    r.evidence.forEach(function (e) {
      var li = document.createElement('li'), tag = document.createElement('span');
      tag.className = 'tag ' + TAGS[e[0]][1]; tag.textContent = TAGS[e[0]][0];
      li.append(tag, rich(document.createElement('span'), e[1])); ev.appendChild(li);
    });
    setState('investigating', 'Awaiting approval');
    approve.hidden = false; reject.hidden = false; replay.hidden = true;
  }
  function decide(cls, href, text) {
    var gate = $('gate');
    gate.querySelector('.dot').className = 'dot ' + cls;
    gate.querySelector('use').setAttribute('href', href);
    gate.children[1].textContent = text;
    gate.children[2].textContent = 'human';
    approve.hidden = true; reject.hidden = true; replay.hidden = false; replay.focus();
  }

  if (runsEl && RUNS.length > 1) {
    RUNS.forEach(function (r, i) {
      var b = document.createElement('button');
      b.type = 'button'; b.className = 'inc';
      var row = document.createElement('span'); row.className = 'row';
      var n = document.createElement('span'); n.textContent = r.name;
      var k = document.createElement('span'); k.className = 'sev ' + r.sev; k.textContent = r.kind;
      row.append(n, k);
      var a = document.createElement('span'); a.className = 'mono who'; a.textContent = r.sub;
      b.append(row, a);
      b.addEventListener('click', function () { render(i); });
      runsEl.appendChild(b);
    });
  }
  approve.addEventListener('click', function () {
    decide('ok', '#i-check', 'Approved by you');
    RUNS[current].applied.forEach(function (s) { step('ok', '#i-check', s[0], s[1], true); });
    setState('resolved', 'Completed');
    $('note').textContent = 'Carried out by people and pipelines, not the agent';
  });
  reject.addEventListener('click', function () {
    decide('no', '#i-x', 'Rejected by you: nothing was changed');
    setState('blocked', 'Rejected');
    $('note').textContent = 'The agent keeps working read-only';
  });
  replay.addEventListener('click', function () { render(current); approve.focus(); });
  render(0);
})();
