%% Census Area Profile - Data Cleaning & Analysis
% Reads census_area_profile.xlsx (sheets "Headline", "Distributions", "Info"),
% cleans it, writes Excel summary files, and draws dark-themed pie charts,
% bar charts and a histogram.
%   Headline      one row per single-number statistic, with comparison areas
%   Distributions one row per bar/slice of each chart in the profile
clear; clc; close all;

%% 0. SETTINGS
filename      = "census_area_profile.xlsx";   % keep this file in MATLAB's current folder
headlineSheet = "Headline";
distSheet     = "Distributions";
infoSheet     = "Info";
outputFolder  = "analysis_output";
saveFigures   = true;      % also save every figure as a PNG
missingTokens = ["", "NA", "N/A", "NAN", "NULL", "ERROR", "UNKNOWN", "-", "--"];  % not case-sensitive

% Column names in the Headline sheet (first = the area being profiled)
areaCols    = ["This Area", "Metro Area", "New Mexico", "United States"];
legendNames = ["This area", "Albuquerque Metro Area", "New Mexico", "United States"];
histCompare = "New Mexico";   % comparison area used for the ratio histogram
shareTol    = 2;              % share charts must add to 100 +/- this many points

daggerNote  = string(char(8224)) + " margin of error is at least 10% of the value (low reliability, per source)";

%% 1. Load the dataset
H = readAllText(filename, headlineSheet);
D = readAllText(filename, distSheet);
I = table();
try
    I = readAllText(filename, infoSheet);
catch
    warning("No '%s' sheet found - using default labels.", infoSheet);
end

geo       = infoLookup(I, "Geography", "Census Area Profile");
yearTxt   = infoLookup(I, "Data year", "");
areaLabel = geo;
if yearTxt ~= "", areaLabel = geo + " (" + yearTxt + ")"; end
if geo ~= "Census Area Profile", legendNames(1) = geo; end   % legends use the area's name

disp("Original Headline preview:");      disp(head(H));
disp("Original Distributions preview:"); disp(head(D));
fprintf("Original rows: %d headline, %d distribution\n", height(H), height(D));

%% 2. Clean the data
% 2a. Headline sheet
requireCols(H, ["Section", "Metric", "Unit", areaCols], headlineSheet);
for v = ["Section", "Metric", "Unit"]
    H.(v) = cleanText(H.(v), missingTokens);
end
if ismember("Note", string(H.Properties.VariableNames))
    H.Note = cleanText(H.Note, missingTokens);
else
    H.Note = repmat(string(missing), height(H), 1);
end
for v = areaCols
    H.(v) = toNumber(H.(v), missingTokens);
end
H(ismissing(H.Metric), :) = [];

% 2b. Distributions sheet
requireCols(D, ["Section", "Chart", "Category", "Value", "Unit"], distSheet);
for opt = ["Figure", "Group", "Flag", "Chart Type", "Note"]
    if ~ismember(opt, string(D.Properties.VariableNames))
        D.(opt) = repmat(string(missing), height(D), 1);
    end
end
for v = ["Figure", "Section", "Chart", "Category", "Group", "Unit", "Flag", "Chart Type", "Note"]
    D.(v) = cleanText(D.(v), missingTokens);
end
D.Value = toNumber(D.Value, missingTokens);

noFig = ismissing(D.Figure);
D.Figure(noFig) = D.Section(noFig);
D.("Chart Type") = lower(D.("Chart Type"));
D.("Chart Type")(~ismember(D.("Chart Type"), ["bar", "pie", "both"])) = "bar";

% Remove blank rows, rows without a value, and duplicates
nBefore = height(D);
D(ismissing(D.Chart) | ismissing(D.Category) | isnan(D.Value), :) = [];
fprintf("Removed %d distribution row(s) with no chart, category or value.\n", nBefore - height(D));

grp = D.Group;  grp(ismissing(grp)) = "";
key = D.Chart + "|" + D.Category + "|" + grp;
[~, keep] = unique(key, 'stable');
if numel(keep) < height(D)
    fprintf("Removed %d duplicate distribution row(s).\n", height(D) - numel(keep));
end
D = D(keep, :);
grp = grp(keep);

% Percent values must lie between 0 and 100
badPct = startsWith(D.Unit, "%") & (D.Value < 0 | D.Value > 100);
if any(badPct)
    warning("%d percent value(s) outside 0-100 (e.g. in '%s').", nnz(badPct), D.Chart(find(badPct, 1)));
end

fprintf("Rows remaining after cleaning: %d headline, %d distribution\n", height(H), height(D));
disp("Cleaned Distributions preview:");
disp(head(D));

%% 3. Summary tables
% 3a. Headline comparison: ratio of This Area to each comparison area
Hc = H;
for k = 2:numel(areaCols)
    ratioName = char("This Area as % of " + areaCols(k));
    ratio = 100 * H.(areaCols(1)) ./ H.(areaCols(k));
    ratio(H.Unit == "count") = NaN;          % ratios of raw counts are not meaningful
    Hc.(ratioName) = ratio;
end

% 3b. One summary row per chart (and per group, for grouped charts)
[~, ia] = unique(table(D.Chart, grp), 'stable');
nP = numel(ia);
CS = table('Size', [nP 9], ...
    'VariableTypes', ["string" "string" "string" "double" "string" "double" "string" "double" "string"], ...
    'VariableNames', {'Section','Chart','Group','Categories','TopCategory','TopValue','Unit','Sum','Status'});
for p = 1:nP
    m = D.Chart == D.Chart(ia(p)) & grp == grp(ia(p));
    sub = D(m, :);
    [mx, k] = max(sub.Value);
    unit = sub.Unit(1);
    if unit == "%"
        sm = sum(sub.Value);
        if abs(sm - 100) <= shareTol
            st = "Complete";
        else
            st = "Incomplete (only some slices in the data)";
        end
    else
        sm = NaN;
        st = "n/a (not a share chart)";
    end
    CS(p, :) = {sub.Section(1), sub.Chart(1), grp(ia(p)), height(sub), sub.Category(k), mx, unit, sm, st};
end

disp("Chart summary:");
disp(CS(:, {'Chart','Group','TopCategory','TopValue','Sum','Status'}));

%% 4. Excel outputs
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end
cleanFile   = fullfile(outputFolder, "cleaned_data.xlsx");
summaryFile = fullfile(outputFolder, "summary_tables.xlsx");
if exist(cleanFile, 'file'),   delete(cleanFile);   end
if exist(summaryFile, 'file'), delete(summaryFile); end

writetable(H, cleanFile, 'Sheet', 'Headline');
writetable(D, cleanFile, 'Sheet', 'Distributions');
writetable(Hc, summaryFile, 'Sheet', 'Headline Comparison');
writetable(CS, summaryFile, 'Sheet', 'Chart Summary');

%% 5. Console highlights
fprintf("\n===== %s =====\n", areaLabel);
for p = 1:nP
    g = "";
    if CS.Group(p) ~= "", g = " [" + CS.Group(p) + "]"; end
    fprintf("%s%s - largest: %s (%g%s)\n", CS.Chart(p), g, CS.TopCategory(p), CS.TopValue(p), ...
        extractBefore(CS.Unit(p) + " ", " "));
end
bad = CS.Chart(startsWith(CS.Status, "Incomplete"));
if ~isempty(bad)
    fprintf("\nCharts with only some slices in the data (pie skipped): %s\n", strjoin(unique(bad, 'stable'), "; "));
end

% Ratios used in the comparison graphs
Hr = H(H.Unit ~= "count" & ~isnan(H.(areaCols(1))), :);
R  = 100 * Hr.(areaCols(1)) ./ table2array(Hr(:, areaCols(2:end)));   % rows = metrics, cols = comparison areas
jHist = find(areaCols(2:end) == histCompare, 1);
if ~isempty(jHist) && ~all(isnan(R(:, jHist)))
    [lo, iLo] = min(R(:, jHist));   [hi, iHi] = max(R(:, jHist));
    fprintf("\nCompared with %s: lowest = %s (%.0f%% of it), highest = %s (%.0f%% of it)\n", ...
        histCompare, Hr.Metric(iLo), lo, Hr.Metric(iHi), hi);
end

%% 6. Graphs: one figure per "Figure" group, one tile per chart
figNames = unique(D.Figure, 'stable');
for fi = 1:numel(figNames)
    Df = D(D.Figure == figNames(fi), :);
    charts = unique(Df.Chart, 'stable');

    tChart = strings(0, 1);   tKind = strings(0, 1);   tSuffix = strings(0, 1);
    for ci = 1:numel(charts)
        sub = Df(Df.Chart == charts(ci), :);
        ct  = sub.("Chart Type")(1);
        if ct == "bar" || ct == "both"
            tChart(end+1, 1) = charts(ci);   tKind(end+1, 1) = "bar"; %#ok<SAGROW>
            tSuffix(end+1, 1) = "";
            if ct == "both", tSuffix(end) = " (bar)"; end
        end
        if ct == "pie" || ct == "both"
            if canPie(sub, shareTol)
                tChart(end+1, 1) = charts(ci);   tKind(end+1, 1) = "pie"; %#ok<SAGROW>
                tSuffix(end+1, 1) = "";
                if ct == "both", tSuffix(end) = " (pie)"; end
            else
                fprintf("Skipping pie chart for '%s' (incomplete or not a share chart).\n", charts(ci));
            end
        end
    end
    if isempty(tChart), continue, end

    fig = newFig(figNames(fi));
    tl = tiledlayout(fig, 'flow', 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, figNames(fi) + " - " + areaLabel);
    if any(~ismissing(Df.Flag)), xlabel(tl, daggerNote); end

    for t = 1:numel(tChart)
        ax  = nexttile(tl);
        sub = Df(Df.Chart == tChart(t), :);
        if tKind(t) == "bar"
            drawBar(ax, sub, tChart(t) + tSuffix(t));
        else
            drawPie(ax, sub, tChart(t) + tSuffix(t));
        end
    end
    saveFig(saveFigures, outputFolder, "fig_" + safeName(figNames(fi)));
end

%% 7. Graph: This Area vs. comparison areas (horizontal bars, one tile per unit)
Hh = H(H.Unit ~= "count" & ~isnan(H.(areaCols(1))), :);
if ~isempty(Hh)
    units = unique(Hh.Unit, 'stable');
    nU = numel(units);
    cnt = arrayfun(@(u) nnz(Hh.Unit == u), units);
    [~, tallIdx] = max(cnt);                              % unit with the most metrics gets a tall tile
    order = [tallIdx, setdiff(1:nU, tallIdx, 'stable')];

    fig = newFig("Comparison");
    if nU <= 2
        tl = tiledlayout(fig, 1, nU, 'TileSpacing', 'compact', 'Padding', 'compact');
    else
        tl = tiledlayout(fig, 2, 1 + ceil((nU-1)/2), 'TileSpacing', 'compact', 'Padding', 'compact');
    end
    title(tl, "This Area vs. Comparison Areas - " + areaLabel);

    firstAx = [];
    for q = 1:nU
        k = order(q);
        sub = Hh(Hh.Unit == units(k), :);
        if nU > 2 && q == 1, ax = nexttile(tl, [2 1]); else, ax = nexttile(tl); end
        if isempty(firstAx), firstAx = ax; end

        Mx = table2array(sub(:, areaCols));
        nM = height(sub);
        if nM == 1, Mx(2, :) = NaN; end      % a single row would be drawn as one series
        b = barh(ax, Mx, 0.85);
        ax.YTick = 1:nM;   ax.YTickLabel = cellstr(sub.Metric);
        ax.YDir = 'reverse';   ax.TickLabelInterpreter = 'none';
        if nM == 1, ylim(ax, [0.4 1.6]); end

        for j = 1:size(Mx, 2)                % value label at the end of each bar
            lbl = strings(size(Mx, 1), 1);
            for i = 1:nM, lbl(i) = valueLabel(Mx(i, j), units(k), false); end
            text(ax, b(j).YEndPoints, b(j).XEndPoints, cellstr(lbl), ...
                'HorizontalAlignment', 'left', 'VerticalAlignment', 'middle');
        end
        mx = max(Mx(:));   if isnan(mx) || mx <= 0, mx = 1; end
        xlim(ax, [0 mx * 1.3]);              % room for the labels
        if units(k) == "$"
            try
                ax.XAxis.Exponent = 0;       % no "x10^5" on the axis
                xtickformat(ax, 'usd');
            catch
            end
        end
        title(ax, unitTitle(units(k)));   grid(ax, 'on');
    end
    lg = legend(firstAx, cellstr(legendNames), 'Orientation', 'horizontal');
    lg.Layout.Tile = 'south';
    saveFig(saveFigures, outputFolder, "fig_comparison");
end

%% 8. Graph: ratios (bar) and their distribution (histogram)
if ~isempty(Hr)
    n = height(Hr);
    fig = newFig("Ratios");
    tl = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
    title(tl, "How This Area Compares - " + areaLabel);

    ax1 = nexttile(tl, [1 2]);
    barh(ax1, 1:n, R, 0.85);
    yticks(ax1, 1:n);   yticklabels(ax1, cellstr(Hr.Metric));
    ax1.YDir = 'reverse';   ax1.TickLabelInterpreter = 'none';
    lg = legend(ax1, cellstr(legendNames(2:end)), 'Orientation', 'horizontal', 'AutoUpdate', 'off');
    lg.Layout.Tile = 'south';
    xline(100, '--', 'Color', [1 1 1], 'LineWidth', 1.5, 'Parent', ax1);
    title(ax1, "This area as % of each comparison area (100 = same)");
    xlabel(ax1, "Percent of comparison value");   grid(ax1, 'on');

    if ~isempty(jHist)
        rr = R(:, jHist);   rr = rr(~isnan(rr));
        if ~isempty(rr)
            ax2 = nexttile(tl);
            top = max(ceil(max(rr)/20) * 20, 40);
            histogram(ax2, rr, 'BinEdges', 0:20:top);
            xline(100, '--', 'Color', [1 1 1], 'LineWidth', 1.5, 'Parent', ax2);
            title(ax2, "Distribution of ratios vs. " + histCompare);
            xlabel(ax2, "This area as % of " + histCompare);
            ylabel(ax2, "Number of metrics");   grid(ax2, 'on');
        end
    end
    saveFig(saveFigures, outputFolder, "fig_ratios");
end

fprintf("\nDone. Results saved in the '%s' folder.\n", outputFolder);


%% ======================= Local functions =======================

function T = readAllText(file, sheet)
% Read a sheet with every column as text; numbers are cleaned later.
    opts = detectImportOptions(file, 'Sheet', sheet, 'VariableNamingRule', 'preserve');
    opts = setvartype(opts, 'string');
    T = readtable(file, opts);
end

function requireCols(T, cols, sheet)
    miss = setdiff(string(cols), string(T.Properties.VariableNames));
    if ~isempty(miss)
        error("The '%s' sheet is missing column(s): %s", sheet, strjoin(miss, ", "));
    end
end

function col = cleanText(col, tokens)
% Trim text and turn blanks / placeholder tokens into <missing>.
    col = strtrim(string(col));
    col(ismissing(col) | ismember(upper(col), upper(tokens))) = missing;
end

function x = toNumber(col, tokens)
% Text -> number, ignoring thousands commas, $ and % signs.
    col = cleanText(col, tokens);
    x = str2double(erase(col, [",", "$", "%", " "]));
end

function out = infoLookup(I, field, fallback)
    out = string(fallback);
    if isempty(I) || ~all(ismember(["Field", "Value"], string(I.Properties.VariableNames))), return, end
    k = find(strtrim(string(I.Field)) == field, 1);
    if ~isempty(k) && ~ismissing(I.Value(k)), out = strtrim(string(I.Value(k))); end
end

function ok = canPie(sub, tol)
% A pie needs ungrouped percent shares that add to ~100 with at least 2 slices.
    ok = all(ismissing(sub.Group)) && all(sub.Unit == "%") && ...
         abs(sum(sub.Value) - 100) <= tol && nnz(sub.Value > 0) >= 2;
end

function s = addCommas(x)
    s = regexprep(sprintf('%d', round(x)), '(\d)(?=(\d{3})+$)', '$1,');
end

function s = valueLabel(v, unit, flagged)
    if isnan(v), s = ""; return, end
    if contains(unit, "$")
        s = "$" + addCommas(v);
    elseif startsWith(unit, "%")
        s = string(sprintf('%g%%', v));
    else
        s = string(sprintf('%g', v));
    end
    if flagged, s = s + string(char(8224)); end
end

function s = unitTitle(unit)
    switch unit
        case "$",  s = "Dollars ($)";
        case "%",  s = "Percent (%)";
        otherwise, s = unit;
    end
end

function drawBar(ax, sub, ttl)
% Bar chart of one chart's categories (grouped bars when a Group column is used).
    cats = unique(sub.Category, 'stable');
    g = sub.Group;   g(ismissing(g)) = "";
    groups = unique(g, 'stable');
    nC = numel(cats);   nG = numel(groups);
    Mx = NaN(nC, nG);   Fl = false(nC, nG);
    for r = 1:height(sub)
        i = find(cats == sub.Category(r), 1);
        j = find(groups == g(r), 1);
        Mx(i, j) = sub.Value(r);
        Fl(i, j) = ~ismissing(sub.Flag(r));
    end
    unit = sub.Unit(1);

    nR = nC;
    if nC == 1 && nG > 1                      % a single row would be drawn as one series
        Mx(2, :) = NaN;   Fl(2, :) = false;   nR = 2;
    end
    b = bar(ax, Mx, 0.8);
    ax.XTick = 1:nC;   ax.XTickLabel = cellstr(cats);
    ax.TickLabelInterpreter = 'none';
    if nR > nC, xlim(ax, [0.4 1.6]); end
    if nC > 4, ax.XTickLabelRotation = 30; end
    for j = 1:nG
        lbl = strings(nR, 1);
        for i = 1:nC, lbl(i) = valueLabel(Mx(i, j), unit, Fl(i, j)); end
        text(ax, b(j).XEndPoints, b(j).YEndPoints, cellstr(lbl), ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
    mx = max(Mx(:));   if isnan(mx) || mx <= 0, mx = 1; end
    ylim(ax, [0 mx * 1.25]);
    if nG > 1 || groups(1) ~= ""
        legend(ax, cellstr(groups), 'Location', 'northeast');
    end
    title(ax, ttl);
    if unit == "%", ylabel(ax, "Percent"); else, ylabel(ax, unit); end
    grid(ax, 'on');
end

function drawPie(ax, sub, ttl)
% Pie of one share chart; zero slices are dropped.
    v = sub.Value;   nm = sub.Category;   fl = ~ismissing(sub.Flag);
    keep = v > 0;
    v = v(keep);   nm = nm(keep);   fl = fl(keep);
    sliceLbls = repmat({''}, 1, numel(v));
    for k = 1:numel(v)
        if 100*v(k)/sum(v) >= 3
            sliceLbls{k} = char(valueLabel(v(k), "%", fl(k)));
        end
    end
    pie(ax, v, sliceLbls);
    legend(ax, cellstr(compose("%s (%g%%)", nm(:), v(:))), 'Location', 'southoutside');
    title(ax, ttl);
end

function fig = newFig(label)
% Large figure with a dark background and a bright color palette
    fig = figure('Name', char(label), 'NumberTitle', 'off', 'Color', [0.09 0.10 0.13], ...
        'Units', 'normalized', 'Position', [0.05 0.06 0.90 0.84]);
    colororder(fig, [0.30 0.75 0.93; 1.00 0.60 0.20; 0.55 0.90 0.45; ...
                     0.95 0.45 0.65; 0.95 0.85 0.30; 0.65 0.55 0.95]);
end

function styleDark()
% Dark background, white text, readable fonts - applied to the current figure
    bg = [0.09 0.10 0.13];   fg = [1 1 1];
    fig = gcf;   fig.Color = bg;

    axs = findall(fig, 'Type', 'axes');
    multi = numel(axs) > 1;
    fsAxes = 13 - 2*multi;   fsTitle = 16 - 3*multi;   fsText = 12 - 2*multi;

    tx = findall(fig, 'Type', 'text');
    for k = 1:numel(tx)
        tx(k).Color = fg;   tx(k).FontSize = fsText;   tx(k).FontWeight = 'bold';
    end

    for k = 1:numel(axs)
        ax = axs(k);
        ax.Color = bg;   ax.XColor = fg;   ax.YColor = fg;   ax.FontSize = fsAxes;
        ax.GridColor = fg;   ax.GridAlpha = 0.25;   ax.MinorGridAlpha = 0.15;
        ax.Title.Color = fg;   ax.Title.FontSize = fsTitle;   ax.Title.FontWeight = 'bold';
        ax.XLabel.Color = fg;  ax.XLabel.FontSize = fsAxes;
        ax.YLabel.Color = fg;  ax.YLabel.FontSize = fsAxes;
    end

    lg = findall(fig, 'Type', 'legend');
    for k = 1:numel(lg)
        lg(k).TextColor = fg;   lg(k).Color = [0.16 0.17 0.21];
        lg(k).EdgeColor = [0.6 0.6 0.65];   lg(k).FontSize = fsAxes;
    end

    tl = findall(fig, 'Type', 'tiledlayout');
    for k = 1:numel(tl)
        tl(k).Title.Color = fg;   tl(k).Title.FontSize = 19;   tl(k).Title.FontWeight = 'bold';
        tl(k).XLabel.Color = fg;  tl(k).XLabel.FontSize = 12;  tl(k).XLabel.FontWeight = 'normal';
    end

    pt = findall(fig, 'Type', 'patch');
    for k = 1:numel(pt)
        pt(k).EdgeColor = bg;   pt(k).LineWidth = 2;
    end
end

function name = safeName(name)
    name = regexprep(char(name), '[^\w\-]', '_');
end

function saveFig(doSave, folder, name)
% Apply the dark style, then save a PNG (keeping the dark background)
    styleDark();
    if doSave
        exportgraphics(gcf, fullfile(folder, char(name) + ".png"), ...
            'Resolution', 200, 'BackgroundColor', 'current');
    end
end
