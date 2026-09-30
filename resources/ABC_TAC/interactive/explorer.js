(function (global) {
  "use strict";

  const TOTAL = "All groundfish";
  const DATASETS = ["AKFIN catch", "Harvest specifications", "NOAA quota-account catch"];
  const METRICS = ["Catch", "ABC", "TAC", "OFL"];
  const DEFINITIONS = {
    "AKFIN catch": "Preliminary AKFIN Economic SAFE catch: retained and discarded FMP groundfish, including groundfish caught while targeting halibut. This series has a broader accounting scope than NOAA quota-account catch.",
    "Harvest specifications": "Published compilation of annual ABC, TAC, and OFL. Species and group names follow the source. Regional totals use the source's selected rows; missing values and repeated labels are retained and flagged. GOA coverage ends in 2024. BSAI sablefish ABC/TAC for 1995–1996 include overlapping regional subtotals and area components; affected points retain source sums and carry notes.",
    "NOAA quota-account catch": "NOAA CAR110 quota-account catch, including BSAI CDQ. Species groups combine the available area and gear accounts. Squid accounts end in 2018 and sculpin accounts end in 2020. Regional totals change with the managed species included."
  };
  const clone = value => JSON.parse(JSON.stringify(value));
  const number = value => value === null || value === undefined || value === "" ? null : Number.isFinite(Number(value)) ? Number(value) : null;
  const unique = values => Array.from(new Set(values));
  const sameSeries = (row, trace) => row.Dataset === trace.Dataset && row.Region === trace.Region && row.Species === trace.Species && row.Measure === trace.Measure;

  function selectRows(rows, state) {
    if (number(state.from) === null || number(state.to) === null) return [];
    const measures = new Set(state.measures);
    const species = new Set(state.view === "total" ? [TOTAL] : state.species);
    return rows.filter(row => row.Dataset === state.dataset && row.Region === state.region && species.has(row.Species) && measures.has(row.Measure) && number(row.Year) !== null && Number(row.Year) >= Number(state.from) && Number(row.Year) <= Number(state.to));
  }

  function normalizeYears(from, to, bounds) {
    let low = number(from), high = number(to);
    if (low !== null) low = Math.max(bounds.min, Math.min(bounds.max, Math.trunc(low)));
    if (high !== null) high = Math.max(bounds.min, Math.min(bounds.max, Math.trunc(high)));
    if (low !== null && high !== null && low > high) [low, high] = [high, low];
    return {from: low, to: high};
  }

  function csvValue(value) {
    if (value === null || value === undefined) return "";
    const text = String(value);
    return /[",\n\r]/.test(text) ? '"' + text.replace(/"/g, '""') + '"' : text;
  }

  function rowsCSV(rows) {
    const columns = ["Dataset", "Region", "Species", "Measure", "Year", "Value_t", "SourceRows", "MissingRows", "Coverage", "RepeatedLabels", "Source", "Notes"];
    return columns.join(",") + "\r\n" + rows.map(row => columns.map(key => csvValue(row[key])).join(",")).join("\r\n") + "\r\n";
  }

  function mount(el, data) {
    if (el.dataset.councilExplorerMounted === "true") return;
    el.dataset.councilExplorerMounted = "true";
    const rows = data.rows || [];
    const traceMetadata = data.traces || [];
    const originalTraces = clone(el.data || []);
    const originalLayout = clone(el.layout || {});
    const datasets = DATASETS.filter(dataset => rows.some(row => row.Dataset === dataset));
    unique(rows.map(row => row.Dataset)).forEach(dataset => { if (!datasets.includes(dataset)) datasets.push(dataset); });
    const state = {dataset: datasets[0] || DATASETS[0], region: "BSAI", view: "total", measures: [], species: [], from: null, to: null};
    let bounds = {min: 0, max: 0}, selectedRows = [], revision = 0;
    let speciesItems = [], resizePending = false;
    const document = el.ownerDocument;

    function node(tag, attrs, text) {
      const element = document.createElement(tag);
      Object.entries(attrs || {}).forEach(([key, value]) => {
        if (key === "className") element.className = value;
        else element.setAttribute(key, value);
      });
      if (text !== undefined) element.textContent = text;
      return element;
    }
    function option(value, text) { return node("option", {value}, text || value); }
    function control(labelText, id, element) {
      const div = node("div", {className: "ce-control"});
      div.append(node("label", {for: id}, labelText), element);
      return div;
    }
    function button(text, id) { return node("button", {type: "button", id}, text); }

    const shell = node("section", {className: "council-explorer", "aria-label": "Interactive groundfish time series"});
    const parent = el.parentNode;
    parent.insertBefore(shell, el);
    const controls = node("div", {className: "ce-controls"});
    const grid = node("div", {className: "ce-control-grid"});
    const source = node("select", {id: "explorer-source"});
    datasets.forEach(dataset => source.append(option(dataset)));
    const region = node("select", {id: "explorer-region"});
    ["BSAI", "GOA"].forEach(value => region.append(option(value)));
    const view = node("select", {id: "explorer-view"});
    view.append(option("total", "All groundfish"), option("species", "Choose species or groups"));
    grid.append(control("Source series", "explorer-source", source), control("Region", "explorer-region", region), control("Show", "explorer-view", view));
    const metricBox = node("fieldset", {className: "ce-metrics", id: "explorer-metrics"});
    const yearGrid = node("div", {className: "ce-year-grid"});
    const from = node("input", {type: "number", id: "explorer-from", step: "1", inputmode: "numeric"});
    const to = node("input", {type: "number", id: "explorer-to", step: "1", inputmode: "numeric"});
    const reset = button("Reset selections and zoom", "explorer-reset");
    const zoom = button("Reset zoom", "explorer-reset-zoom");
    yearGrid.append(control("First year", "explorer-from", from), control("Last year", "explorer-to", to), reset, zoom);
    const speciesBox = node("fieldset", {className: "ce-species", id: "explorer-species"});
    speciesBox.append(node("legend", {}, "Species or groups"));
    const speciesHelp = node("p", {className: "ce-help", id: "explorer-species-help"}, "Each selected species or group is plotted separately. Names follow the source; groupings can change across years.");
    const search = node("input", {type: "search", id: "explorer-search", placeholder: "Find a species or group", "aria-describedby": "explorer-species-help"});
    const speciesActions = node("div", {className: "ce-species-actions"});
    const selectVisible = button("Select visible", "explorer-select-visible");
    const clearSpecies = button("Clear species", "explorer-clear-species");
    speciesActions.append(selectVisible, clearSpecies);
    const speciesList = node("div", {className: "ce-species-list"});
    const noSpecies = node("p", {className: "ce-help", hidden: "hidden"}, "No species or groups match this search.");
    speciesBox.append(speciesHelp, control("Find a species or group", "explorer-search", search), speciesActions, speciesList, noSpecies);
    const definition = node("p", {className: "ce-definition", id: "explorer-definition"});
    const status = node("p", {className: "ce-status", id: "explorer-status", role: "status", "aria-live": "polite", "aria-atomic": "true"});
    controls.append(grid, metricBox, speciesBox, yearGrid, definition, status);
    shell.append(controls, el);
    el.classList.add("ce-plot");
    el.style.width = "100%";
    el.style.height = "500px";
    el.style.minHeight = "500px";
    const footer = node("div", {className: "ce-footer"});
    const download = button("Download selected data (CSV)", "explorer-download");
    footer.append(download, node("p", {className: "ce-help"}, "Hover over a point for details. Drag to zoom; double-click or use Reset zoom to restore the selected years. Click a legend entry to hide or show that line; legend changes affect the chart only. CSV downloads and the table follow the controls above."));
    const details = node("details", {className: "ce-table-details", id: "explorer-table"});
    const summary = node("summary", {}, "Selected data");
    const tableCaption = node("p", {className: "ce-help"});
    const tableScroll = node("div", {className: "ce-table-scroll", tabindex: "0", role: "region", "aria-label": "Selected time-series data table"});
    details.append(summary, tableCaption, tableScroll);
    shell.append(footer, details);

    function resizeFrame() {
      if (resizePending) return;
      resizePending = true;
      global.requestAnimationFrame(() => {
        resizePending = false;
        try {
          // Measure content rather than the iframe viewport so the frame can shrink too.
          const frame = global.frameElement;
          const height = Math.ceil(shell.getBoundingClientRect().bottom + global.scrollY + 24);
          if (frame && Math.abs(frame.getBoundingClientRect().height - height) > 2) frame.style.height = height + "px";
        } catch (_) { /* Standalone and cross-origin embeds keep their normal height. */ }
      });
    }

    function contextRows() { return rows.filter(row => row.Dataset === state.dataset && row.Region === state.region); }
    function chooseFirstSpecies(names) { return names.find(name => /pollock/i.test(name)) || names[0]; }

    function setupContext(resetMeasures, resetYears) {
      let context = contextRows();
      const regions = unique(rows.filter(row => row.Dataset === state.dataset).map(row => row.Region));
      if (!regions.includes(state.region)) { state.region = regions[0] || "BSAI"; context = contextRows(); }
      Array.from(region.options).forEach(item => { item.disabled = !regions.includes(item.value); });
      region.value = state.region;
      const measures = unique(context.map(row => row.Measure)).sort((a, b) => METRICS.indexOf(a) - METRICS.indexOf(b));
      if (resetMeasures) state.measures = measures.slice();
      else state.measures = state.measures.filter(measure => measures.includes(measure));
      metricBox.replaceChildren(node("legend", {}, "Values to plot"));
      measures.forEach((measure, index) => {
        const label = node("label", {className: "ce-check"});
        const checkbox = node("input", {type: "checkbox", id: "explorer-measure-" + index, value: measure});
        checkbox.checked = state.measures.includes(measure);
        checkbox.addEventListener("change", () => { state.measures = Array.from(metricBox.querySelectorAll("input:checked")).map(input => input.value); render(); });
        label.append(checkbox, node("span", {}, measure)); metricBox.append(label);
      });
      const names = unique(context.map(row => row.Species)).filter(name => name !== TOTAL).sort((a, b) => a.localeCompare(b));
      state.species = state.species.filter(name => names.includes(name));
      if (!state.species.length && names.length) state.species = [chooseFirstSpecies(names)];
      speciesList.replaceChildren();
      speciesItems = names.map((name, index) => {
        const label = node("label", {className: "ce-check"});
        const checkbox = node("input", {type: "checkbox", id: "explorer-species-" + index, value: name});
        checkbox.checked = state.species.includes(name);
        checkbox.addEventListener("change", () => { state.species = speciesItems.filter(item => item.checkbox.checked).map(item => item.name); render(); });
        label.append(checkbox, node("span", {}, name)); speciesList.append(label);
        return {name, label, checkbox};
      });
      search.value = "";
      filterSpecies();
      const years = context.map(row => number(row.Year)).filter(value => value !== null);
      bounds = {min: years.length ? Math.min(...years) : 0, max: years.length ? Math.max(...years) : 0};
      if (resetYears) { state.from = bounds.min; state.to = bounds.max; }
      else Object.assign(state, normalizeYears(state.from, state.to, bounds));
      [from, to].forEach(input => { input.min = String(bounds.min); input.max = String(bounds.max); });
      from.value = state.from === null ? "" : state.from;
      to.value = state.to === null ? "" : state.to;
      source.value = state.dataset;
      view.value = state.view;
      speciesBox.hidden = state.view !== "species";
      definition.textContent = DEFINITIONS[state.dataset] || "Values and species names follow the selected source.";
    }

    function filterSpecies() {
      const query = search.value.trim().toLocaleLowerCase();
      speciesItems.forEach(item => { item.label.hidden = !item.name.toLocaleLowerCase().includes(query); });
      noSpecies.hidden = speciesItems.some(item => !item.label.hidden);
      resizeFrame();
    }

    function filteredTrace(meta) {
      const original = originalTraces[Number(meta.index)];
      if (!original || !Array.isArray(original.x)) return null;
      const trace = clone(original);
      const keep = original.x.map((year, index) => ({year: number(year), index})).filter(item => item.year !== null && item.year >= state.from && item.year <= state.to).map(item => item.index);
      ["x", "y", "text", "hovertext", "customdata", "ids"].forEach(key => { if (Array.isArray(original[key]) && original[key].length === original.x.length) trace[key] = keep.map(index => original[key][index]); });
      if (!Array.isArray(trace.y) || !trace.y.some(value => number(value) !== null)) return null;
      if (trace.marker) ["size", "color", "symbol", "opacity"].forEach(key => { if (Array.isArray(original.marker[key]) && original.marker[key].length === original.x.length) trace.marker[key] = keep.map(index => original.marker[key][index]); });
      trace.name = meta.Species + " — " + meta.Measure;
      trace.legendgroup = [meta.Dataset, meta.Region, meta.Species, meta.Measure].join("|");
      trace.visible = true;
      trace.showlegend = true;
      trace.connectgaps = false;
      return trace;
    }

    function selectedTraces() {
      if (!selectedRows.length) return [];
      const measures = new Set(state.measures);
      const species = new Set(state.view === "total" ? [TOTAL] : state.species);
      return traceMetadata.filter(meta => meta.Dataset === state.dataset && meta.Region === state.region && species.has(meta.Species) && measures.has(meta.Measure)).map(filteredTrace).filter(Boolean);
    }

    function makeLayout(hasData) {
      const layout = clone(originalLayout);
      layout.autosize = true;
      delete layout.width;
      layout.height = 500;
      layout.uirevision = "selection-" + (++revision);
      layout.title = {text: state.region + " · " + state.dataset, x: 0.02, xanchor: "left", font: {size: 17}};
      Object.keys(layout).filter(key => /^[xy]axis\d*$/.test(key)).forEach(key => {
        // ggplotly saves ticks for the original data range; recompute after selection.
        ["range", "tickvals", "ticktext", "categoryarray", "categoryorder", "dtick", "tick0"].forEach(attribute => { delete layout[key][attribute]; });
        layout[key].tickmode = "auto";
        layout[key].autorange = true;
        if (/^yaxis/.test(key)) layout[key].rangemode = "tozero";
      });
      layout.xaxis = Object.assign({}, layout.xaxis, {title: {text: "Year"}, tickformat: "d", fixedrange: false});
      if (state.from !== null && state.to !== null) { layout.xaxis.range = state.from === state.to ? [state.from - 0.5, state.to + 0.5] : [state.from, state.to]; layout.xaxis.autorange = false; }
      if (state.from !== null && state.to !== null && state.to - state.from < 6) { layout.xaxis.tickmode = "linear"; layout.xaxis.dtick = 1; layout.xaxis.tick0 = state.from; }
      layout.yaxis = Object.assign({}, layout.yaxis, {title: {text: "Metric tons"}, rangemode: "tozero", autorange: true, fixedrange: false});
      layout.margin = Object.assign({}, layout.margin, {t: 55, l: 76, r: 24, b: 75});
      layout.legend = Object.assign({}, layout.legend, {orientation: "h", x: 0, y: -0.18, xanchor: "left", yanchor: "top", title: {text: ""}});
      layout.annotations = [];
      if (!hasData) layout.annotations.push({text: "No values for this selection.<br>Choose a series, species, and valid year range.", xref: "paper", yref: "paper", x: 0.5, y: 0.5, showarrow: false, font: {size: 15, color: "#495361"}, align: "center"});
      return layout;
    }

    function renderTable() {
      const limit = 1000;
      const ordered = selectedRows.slice().sort((a, b) => a.Species.localeCompare(b.Species) || a.Measure.localeCompare(b.Measure) || Number(a.Year) - Number(b.Year));
      summary.textContent = "Selected data (" + ordered.length.toLocaleString() + " rows)";
      tableCaption.textContent = ordered.length > limit ? "Showing the first " + limit.toLocaleString() + " rows. Download the CSV for all " + ordered.length.toLocaleString() + " selected rows, source details, and notes." : "Values are metric tons. A dash marks a missing source value. The CSV includes source details and notes.";
      tableScroll.replaceChildren();
      if (!details.open) return;
      if (!ordered.length) { tableScroll.append(node("p", {}, "No rows match the controls above.")); return; }
      const table = node("table");
      table.append(node("caption", {className: "ce-visually-hidden"}, state.region + " " + state.dataset + ": selected annual values"));
      const thead = node("thead"), heading = node("tr");
      ["Species or group", "Measure", "Year", "Metric tons", "Coverage", "Missing rows", "Repeated labels"].forEach(text => heading.append(node("th", {scope: "col"}, text)));
      thead.append(heading); table.append(thead);
      const tbody = node("tbody");
      ordered.slice(0, limit).forEach(row => {
        const tr = node("tr");
        const value = number(row.Value_t);
        [row.Species, row.Measure, row.Year, value === null ? "—" : value.toLocaleString(undefined, {maximumFractionDigits: 3}), row.Coverage || "—", row.MissingRows ?? "—", row.RepeatedLabels ?? "—"].forEach((text, index) => tr.append(node(index === 0 ? "th" : "td", index === 0 ? {scope: "row"} : index >= 2 && index !== 4 ? {className: "ce-number"} : {}, String(text))));
        tbody.append(tr);
      });
      table.append(tbody); tableScroll.append(table);
    }

    function render() {
      selectedRows = selectRows(rows, state);
      const traces = selectedTraces();
      const available = selectedRows.filter(row => number(row.Value_t) !== null);
      const gaps = selectedRows.length - available.length;
      const incomplete = selectedRows.filter(row => Number(row.MissingRows) > 0 || /partial|incomplete/i.test(String(row.Coverage || ""))).length;
      const repeated = selectedRows.filter(row => Number(row.RepeatedLabels) > 0).length;
      const actualYears = available.map(row => Number(row.Year));
      let message;
      if (!state.measures.length) message = "Choose at least one value to plot.";
      else if (state.view === "species" && !state.species.length) message = "Choose at least one species or group.";
      else if (state.from === null || state.to === null) message = "Enter both the first and last year.";
      else if (!available.length) message = "No available values match this selection. Missing source rows remain available in the CSV.";
      else message = traces.length + " plotted series · " + available.length.toLocaleString() + " annual values · " + Math.min(...actualYears) + "–" + Math.max(...actualYears) + ".";
      if (gaps) message += " " + gaps + " missing annual value" + (gaps === 1 ? "" : "s") + ".";
      if (incomplete) message += " " + incomplete + " annual row" + (incomplete === 1 ? " has" : "s have") + " incomplete source coverage.";
      if (repeated) message += " " + repeated + " annual row" + (repeated === 1 ? " retains" : "s retain") + " repeated source labels.";
      if (state.dataset === "AKFIN catch") message += " Preliminary catch estimates.";
      status.textContent = message;
      download.disabled = selectedRows.length === 0;
      renderTable();
      if (!global.Plotly || typeof global.Plotly.react !== "function") { status.textContent = "The chart library could not load. The selected data table and CSV download are available."; resizeFrame(); return; }
      global.Plotly.react(el, traces, makeLayout(traces.length > 0), {responsive: true, displaylogo: false, scrollZoom: false, toImageButtonOptions: {filename: "groundfish-time-series", format: "png", scale: 2}}).then(resizeFrame).catch(() => { status.textContent = "The chart could not be drawn. The selected data table and CSV download are available."; resizeFrame(); });
      resizeFrame();
    }

    source.addEventListener("change", () => { state.dataset = source.value; setupContext(true, true); render(); });
    region.addEventListener("change", () => { state.region = region.value; setupContext(false, true); render(); });
    view.addEventListener("change", () => { state.view = view.value; speciesBox.hidden = state.view !== "species"; render(); });
    [from, to].forEach(input => input.addEventListener("change", () => { Object.assign(state, normalizeYears(from.value, to.value, bounds)); from.value = state.from === null ? "" : state.from; to.value = state.to === null ? "" : state.to; render(); }));
    search.addEventListener("input", filterSpecies);
    selectVisible.addEventListener("click", () => { speciesItems.filter(item => !item.label.hidden).forEach(item => { item.checkbox.checked = true; }); state.species = speciesItems.filter(item => item.checkbox.checked).map(item => item.name); render(); });
    clearSpecies.addEventListener("click", () => { speciesItems.forEach(item => { item.checkbox.checked = false; }); state.species = []; render(); });
    reset.addEventListener("click", () => { Object.assign(state, {dataset: datasets[0] || DATASETS[0], region: "BSAI", view: "total", species: []}); setupContext(true, true); render(); });
    zoom.addEventListener("click", () => { render(); });
    details.addEventListener("toggle", () => { renderTable(); resizeFrame(); });
    download.addEventListener("click", () => {
      if (!selectedRows.length) return;
      const blob = new Blob([rowsCSV(selectedRows)], {type: "text/csv;charset=utf-8"});
      const url = URL.createObjectURL(blob);
      const anchor = node("a", {href: url, download: (state.region + "_" + state.dataset + "_" + state.from + "-" + state.to).replace(/[^a-zA-Z0-9_-]+/g, "_") + ".csv"});
      document.body.append(anchor); anchor.click(); anchor.remove();
      global.setTimeout(() => URL.revokeObjectURL(url), 1000);
    });
    if (typeof global.ResizeObserver === "function") new global.ResizeObserver(resizeFrame).observe(shell);
    global.addEventListener("resize", resizeFrame);
    setupContext(true, true);
    render();
    // Expose the selection only for transparent, read-only inspection and verification.
    el.councilExplorer = {getState: () => clone(state), getSelectedRows: () => clone(selectedRows)};
  }

  const api = {mount, selectRows, normalizeYears, rowsCSV, sameSeries};
  global.CouncilExplorer = api;
  if (typeof module !== "undefined" && module.exports) module.exports = api;
})(typeof window !== "undefined" ? window : globalThis);
