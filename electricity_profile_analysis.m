%% State Electricity Profile - Data Cleaning & Analysis
% Reads new_mexico_electricity_2024.xlsx (sheets "Data" and "Info"), cleans
% it, writes Excel summary files, and draws pie charts, bar charts and a
% histogram. Any other state's EIA "Table 1" typed into the same layout
% (Section | Item | Unit | Value | Rank | Level) will work too.
clear; clc; close all;

%% 0. SETTINGS
filename      = "new_mexico_electricity_2024.xlsx";   % keep this file in MATLAB's current folder
dataSheet     = "Data";
infoSheet     = "Info";
outputFolder  = "analysis_output";
saveFigures   = true;      % also save every graph as a PNG
missingTokens = ["", "NA", "N/A", "NAN", "NULL", "ERROR", "UNKNOWN", "-", "--"];  % not case-sensitive

%% 1. Load the dataset
opts = detectImportOptions(filename, 'Sheet', dataSheet, 'VariableNamingRule', 'preserve');
opts = setvartype(opts, 'string');          % read everything as text; numbers are cleaned below
T = readtable(filename, opts);

required = ["Section", "Item", "Unit", "Value", "Rank", "Level"];
missingCols = setdiff(required, string(T.Properties.VariableNames));
if ~isempty(missingCols)
    error("The '%s' sheet is missing column(s): %s", dataSheet, strjoin(missingCols, ", "));
end

% Optional info sheet (state name, year, primary energy source)
I = table();
try
    iopts = detectImportOptions(filename, 'Sheet', infoSheet, 'VariableNamingRule', 'preserve');
    iopts = setvartype(iopts, 'string');
    I = readtable(filename, iopts);
catch
    warning("No '%s' sheet found - using default labels.", infoSheet);
end
stateName     = infoLookup(I, "State", "State");
yearLabel     = infoLookup(I, "Year", "");
primarySource = infoLookup(I, "Primary energy source", "n/a");
runLabel      = strtrim(stateName + " " + yearLabel);

disp("Original data preview:");
disp(head(T));
fprintf("Original number of rows: %d\n", height(T));

%% 2. Clean the data
% 2a. Trim text and turn placeholder tokens into <missing>
for v = ["Section", "Item", "Unit", "Level"]
    col = strtrim(string(T.(v)));
    col(ismissing(col) | ismember(upper(col), upper(missingTokens))) = missing;
    T.(v) = col;
end

% 2b. Convert Value and Rank to numbers (removes thousands commas)
for v = ["Value", "Rank"]
    col = strtrim(string(T.(v)));
    col(ismissing(col) | ismember(upper(col), upper(missingTokens))) = missing;
    T.(v) = str2double(erase(col, ","));
end
T.Rank(T.Rank <= 0) = NaN;      % a rank of 0 in the source means "not ranked"

% 2c. Remove blank rows and duplicates
T(ismissing(T.Section) & ismissing(T.Item), :) = [];
[~, keep] = unique(T(:, ["Section", "Item", "Unit"]), 'stable');
nDup = height(T) - numel(keep);
T = T(keep, :);
if nDup > 0, fprintf("Removed %d duplicate row(s).\n", nDup); end

% 2d. Repair / check totals: Total = sum of its components
partSections = ["Net summer capacity", "Net generation", "Total retail sales"];
for s = partSections
    iTot  = find(T.Section == s & T.Level == "Total");
    iPart = find(T.Section == s & T.Level == "Component");
    if numel(iTot) ~= 1 || isempty(iPart), continue, end
    partsSum = sum(T.Value(iPart), 'omitnan');
    if isnan(T.Value(iTot)) && partsSum > 0
        T.Value(iTot) = partsSum;
        fprintf("Filled missing total for '%s' from its components.\n", s);
    elseif abs(T.Value(iTot) - partsSum) > 0.5
        warning("'%s': components add to %g but the total is %g.", s, partsSum, T.Value(iTot));
    end
end

% 2e. Keep only rows with a valid Value
Tclean = T(~isnan(T.Value), :);
fprintf("Rows remaining after cleaning (valid Value): %d\n", height(Tclean));
disp("Cleaned data preview:");
disp(head(Tclean));

% Readable label for each metric (used in tables and charts)
metricLabel = Tclean.Section;
for i = 1:height(Tclean)
    if Tclean.Item(i) ~= "Total"
        metricLabel(i) = Tclean.Section(i) + " - " + Tclean.Item(i);
    end
    if Tclean.Section(i) == "Emissions"
        metricLabel(i) = metricLabel(i) + " (" + Tclean.Unit(i) + ")";
    end
end

%% 3. Pull out the key values
cap     = "Net summer capacity";   gen = "Net generation";
capTot  = getVal(Tclean, cap, "Total");
capUtil = getVal(Tclean, cap, "Electric utilities");
capIPP  = getVal(Tclean, cap, "IPP & CHP");
genTot  = getVal(Tclean, gen, "Total");
genUtil = getVal(Tclean, gen, "Electric utilities");
genIPP  = getVal(Tclean, gen, "IPP & CHP");
retTot  = getVal(Tclean, "Total retail sales", "Total");
direct  = getVal(Tclean, "Direct use", "Total");

if ~isempty(yearLabel) && ~isnan(str2double(yearLabel))
    yr = str2double(yearLabel);
    hoursInYear = hours(datetime(yr+1,1,1) - datetime(yr,1,1));   % 8784 in a leap year
else
    hoursInYear = 8760;
end

pct = @(a, b) 100 * a ./ b;
remainder = genTot - retTot - direct;      % generation not sold at retail or used directly

%% 4. Summary tables -> Excel
if ~exist(outputFolder, 'dir'), mkdir(outputFolder); end
cleanFile   = fullfile(outputFolder, "cleaned_data.xlsx");
summaryFile = fullfile(outputFolder, "summary_tables.xlsx");
if exist(cleanFile, 'file'),   delete(cleanFile);   end
if exist(summaryFile, 'file'), delete(summaryFile); end

writetable(Tclean, cleanFile, 'Sheet', 'Cleaned Data');

% Key metrics (derived from the table)
km = table( ...
    ["Electric utilities share of net summer capacity"; "IPP & CHP share of net summer capacity"; ...
     "Electric utilities share of net generation"; "IPP & CHP share of net generation"; ...
     "Capacity factor, overall (approx.)"; "Capacity factor, electric utilities (approx.)"; ...
     "Capacity factor, IPP & CHP (approx.)"; "Retail sales as % of net generation"; ...
     "Direct use as % of net generation"; "Net generation not in retail sales or direct use"; ...
     "...as % of net generation"], ...
    [pct(capUtil, capTot); pct(capIPP, capTot); pct(genUtil, genTot); pct(genIPP, genTot); ...
     pct(genTot, capTot*hoursInYear); pct(genUtil, capUtil*hoursInYear); pct(genIPP, capIPP*hoursInYear); ...
     pct(retTot, genTot); pct(direct, genTot); remainder; pct(remainder, genTot)], ...
    ["%"; "%"; "%"; "%"; "%"; "%"; "%"; "%"; "%"; "MWh"; "%"], ...
    'VariableNames', {'Metric', 'Value', 'Unit'});
disp("Key metrics:");
disp(km);
writetable(km, summaryFile, 'Sheet', 'Key Metrics');

% Rank summary (how the state compares with the rest of the U.S.)
rankMask = ~isnan(Tclean.Rank);
[r, ord] = sort(Tclean.Rank(rankMask));
rLabels  = metricLabel(rankMask);   rLabels = rLabels(ord);
rValues  = Tclean.Value(rankMask);  rValues = rValues(ord);
rUnits   = Tclean.Unit(rankMask);   rUnits  = rUnits(ord);

rankStats = table(numel(r), min(r), median(r), mean(r), max(r), ...
    'VariableNames', {'RankedMetrics', 'BestRank', 'MedianRank', 'MeanRank', 'WorstRank'});
disp("Summary statistics for state ranks (1 = highest in the U.S.):");
disp(rankStats);
writetable(rankStats, summaryFile, 'Sheet', 'Rank Summary');
writetable(table(rLabels, rValues, rUnits, r, 'VariableNames', {'Metric','Value','Unit','Rank'}), ...
    summaryFile, 'Sheet', 'Rank Table');

%% 5. Console highlights
fprintf("\nPrimary energy source: %s\n", primarySource);
if ~any(isnan([capUtil capIPP]))
    capParts = [capUtil capIPP];
    [~, i] = max(capParts);  names = ["Electric utilities", "IPP & CHP"];
    fprintf("Largest owner type by capacity: %s (%.1f%%)\n", names(i), pct(capParts(i), capTot));
end
if ~any(isnan([genUtil genIPP]))
    genParts = [genUtil genIPP];
    [~, i] = max(genParts);  names = ["Electric utilities", "IPP & CHP"];
    fprintf("Largest owner type by generation: %s (%.1f%%)\n", names(i), pct(genParts(i), genTot));
end
if ~isempty(r)
    fprintf("Metric ranked closest to #1: %s (#%d)\n", rLabels(1), r(1));
    fprintf("Metric ranked furthest from #1: %s (#%d)\n", rLabels(end), r(end));
end

%% 6. Graphs
owners = ["Electric utilities", "IPP & CHP"];

% 6a. Pie: net summer capacity by owner type
drawPie([capUtil capIPP], owners, "Net Summer Capacity by Owner Type - " + runLabel, ...
    runLabel, saveFigures, outputFolder, "pie_capacity");

% 6b. Pie: net generation by owner type
drawPie([genUtil genIPP], owners, "Net Generation by Owner Type - " + runLabel, ...
    runLabel, saveFigures, outputFolder, "pie_generation");

% 6c. Pie: where the generated electricity goes
if remainder >= 0
    drawPie([retTot direct remainder], ...
        ["Retail sales", "Direct use", "Remainder (e.g. exports, losses)"], ...
        "Disposition of Net Generation - " + runLabel, runLabel, saveFigures, outputFolder, "pie_disposition");
end

% 6d. Bar: electricity flows (million MWh)
simpleBar(["Net generation", "Total retail sales", "Direct use"], [genTot retTot direct]/1e6, ...
    "Electricity Generated vs. Sold vs. Used Directly - " + runLabel, "Million MWh", "%.2f", ...
    runLabel, saveFigures, outputFolder, "bar_flows", false);

% 6e. Bar: approximate capacity factor
simpleBar(["Overall", owners], [pct(genTot, capTot*hoursInYear), ...
    pct(genUtil, capUtil*hoursInYear), pct(genIPP, capIPP*hoursInYear)], ...
    {char("Approximate Capacity Factor - " + runLabel), '(net generation / (net summer capacity x hours in year))'}, ...
    "Percent", "%.1f%%", runLabel, saveFigures, outputFolder, "bar_capacity_factor", false);

% 6f. Bar: emission totals (SO2 and NOx share units; CO2 is in different units)
emTot = Tclean(Tclean.Section == "Emissions" & Tclean.Unit == "short tons", :);
emCO2 = Tclean(Tclean.Section == "Emissions" & Tclean.Unit == "thousand metric tons", :);
if ~isempty(emTot)
    t2 = char("Total Emissions (short tons) - " + runLabel);
    if ~isempty(emCO2)
        t2 = {t2, sprintf('%s: %s thousand metric tons (different units, not shown)', ...
            char(emCO2.Item(1)), formatNumber(emCO2.Value(1), "%,d"))};
    end
    simpleBar(emTot.Item, emTot.Value, t2, "Short tons", "%,d", ...
        runLabel, saveFigures, outputFolder, "bar_emission_totals", false);
end

% 6g. Bar: emission intensity (lbs/MWh), log scale because values differ widely
emRate = Tclean(Tclean.Section == "Emissions" & Tclean.Unit == "lbs/MWh", :);
if ~isempty(emRate)
    simpleBar(emRate.Item, emRate.Value, "Emission Rates (lbs per MWh, log scale) - " + runLabel, ...
        "lbs/MWh", "%g", runLabel, saveFigures, outputFolder, "bar_emission_rates", true);
end

% 6h. Horizontal bar: state rank for every ranked metric
if ~isempty(r)
    n = numel(r);
    newFig(runLabel);
    barh(1:n, r(:), 0.6);
    yticks(1:n); yticklabels(cellstr(rLabels));
    set(gca, 'YDir', 'reverse', 'TickLabelInterpreter', 'none');
    text(r(:)' + 0.8, 1:n, cellstr("#" + string(r(:)')), 'VerticalAlignment', 'middle');
    xlim([0 max(r) + 8]);
    title("State Rank by Metric - " + runLabel);
    xlabel("Rank among U.S. states (1 = highest value)"); grid on;
    saveFig(saveFigures, outputFolder, "bar_ranks");

    % 6i. Histogram: distribution of the ranks
    newFig(runLabel);
    edges = 0.5:10:(ceil(max(r)/10)*10 + 0.5);
    histogram(r, 'BinEdges', edges);
    title("Distribution of State Ranks Across Metrics - " + runLabel);
    xlabel("Rank (1 = highest in the U.S.)"); ylabel("Number of metrics"); grid on;
    saveFig(saveFigures, outputFolder, "hist_ranks");
end

fprintf("\nDone. Results saved in the '%s' folder.\n", outputFolder);


%% ======================= Local functions =======================

function v = getVal(T, section, item, unit)
% Return the single Value matching Section/Item (and Unit if given), else NaN.
    idx = T.Section == section & T.Item == item;
    if nargin >= 4, idx = idx & T.Unit == unit; end
    if nnz(idx) ~= 1, v = NaN; else, v = T.Value(find(idx)); end %#ok<FNDSB>
end

function out = infoLookup(I, field, fallback)
    out = string(fallback);
    if isempty(I) || ~all(ismember(["Field", "Value"], string(I.Properties.VariableNames))), return, end
    k = find(strtrim(string(I.Field)) == field, 1);
    if ~isempty(k) && ~ismissing(I.Value(k)), out = strtrim(string(I.Value(k))); end
end

function newFig(label)
% Large figure with a dark background and a bright color palette
    fig = figure('Name', char(label), 'NumberTitle', 'off', 'Color', [0.09 0.10 0.13], ...
        'Units', 'normalized', 'Position', [0.08 0.08 0.84 0.82]);
    colororder(fig, [0.30 0.75 0.93; 1.00 0.60 0.20; 0.55 0.90 0.45; ...
                     0.95 0.45 0.65; 0.95 0.85 0.30; 0.65 0.55 0.95]);
end

function styleDark()
% Dark background, white text, bigger fonts - applied to the current figure
    bg = [0.09 0.10 0.13];   fg = [1 1 1];
    fig = gcf;   fig.Color = bg;

    % All free text (bar value labels, pie labels): white and larger
    tx = findall(fig, 'Type', 'text');
    for k = 1:numel(tx)
        tx(k).Color = fg;   tx(k).FontSize = 13;   tx(k).FontWeight = 'bold';
    end

    % Axes: dark panel, white ticks/labels/title, soft grid
    axs = findall(fig, 'Type', 'axes');
    for k = 1:numel(axs)
        ax = axs(k);
        ax.Color = bg;   ax.XColor = fg;   ax.YColor = fg;   ax.FontSize = 13;
        ax.GridColor = fg;   ax.GridAlpha = 0.25;   ax.MinorGridAlpha = 0.15;
        ax.Title.Color = fg;   ax.Title.FontSize = 16;   ax.Title.FontWeight = 'bold';
        ax.XLabel.Color = fg;  ax.XLabel.FontSize = 14;
        ax.YLabel.Color = fg;  ax.YLabel.FontSize = 14;
    end

    % Legends
    lg = findall(fig, 'Type', 'legend');
    for k = 1:numel(lg)
        lg(k).TextColor = fg;   lg(k).Color = [0.16 0.17 0.21];
        lg(k).EdgeColor = [0.6 0.6 0.65];   lg(k).FontSize = 13;
    end

    % Pie slices: thin dark outline so the slices stand apart
    pt = findall(fig, 'Type', 'patch');
    for k = 1:numel(pt)
        pt(k).EdgeColor = bg;   pt(k).LineWidth = 2;
    end
end

function saveFig(doSave, folder, name)
% Apply the dark style, then save a PNG (keeping the dark background)
    styleDark();
    if doSave
        exportgraphics(gcf, fullfile(folder, char(name) + ".png"), ...
            'Resolution', 200, 'BackgroundColor', 'current');
    end
end

function drawPie(values, names, ttl, label, doSave, folder, fname)
    names = string(names);
    keep = values > 0 & ~isnan(values);
    if nnz(keep) < 1, return, end
    values = values(keep);  names = names(keep);
    pctv = 100*values(:)/sum(values);
    lbls = cellstr(compose("%s (%.1f%%)", names(:), pctv));   % legend: name + percent

    % On-slice labels show only the percent, and only for slices big enough to fit
    sliceLbls = repmat({''}, 1, numel(values));
    for k = 1:numel(values)
        if pctv(k) >= 3, sliceLbls{k} = sprintf('%.1f%%', pctv(k)); end
    end

    newFig(label);
    pie(values, sliceLbls);
    title(ttl);
    legend(lbls, 'Location', 'eastoutside');
    saveFig(doSave, folder, fname);
end

function simpleBar(names, vals, ttl, ylab, fmt, label, doSave, folder, fname, useLog)
    names = string(names);
    ok = ~isnan(vals);
    names = names(ok);  vals = vals(ok);
    if isempty(vals), return, end
    n = numel(vals);
    newFig(label);
    bar(1:n, vals, 0.6);
    xticks(1:n);  xticklabels(cellstr(names));
    set(gca, 'TickLabelInterpreter', 'none');
    if useLog
        set(gca, 'YScale', 'log');
        ylim([min(vals)/3, max(vals)*4]);
    else
        ylim([0, max(vals)*1.15]);
    end
    labels = cellstr(arrayfun(@(x) formatNumber(x, fmt), vals, 'UniformOutput', false));
    text(1:n, vals(:)', labels, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    title(ttl);  ylabel(ylab);  grid on;
    saveFig(doSave, folder, fname);
end

function s = formatNumber(x, fmt)
% sprintf with thousands separators when fmt is "%,d"
    if fmt == "%,d"
        s = regexprep(sprintf('%d', round(x)), '(\d)(?=(\d{3})+$)', '$1,');
    else
        s = sprintf(char(fmt), x);
    end
end
