%% ANÁLISIS DE EPISODIOS DE ESTRÉS DE LIQUIDEZ
% Series analizadas:
%   - Retiros SF        (col 2): negativo = salida de liquidez
%   - Compras netas mesa (col 3): negativo = salida de liquidez
%
% Metodología: clustering de días de flujo negativo con tolerancia de gap.
% Un episodio = bloque de días negativos separados por ≤ GAP días positivos.
% Se rankean por flujo negativo acumulado dentro del episodio.

clc; clear; close all;

%% ============================================================
%% PARÁMETROS — modificar aquí
%% ============================================================

GAP_1D       = 1;    % días positivos tolerados antes de cerrar episodio
GAP_2D       = 2;    % ídem versión 2

MIN_DURACION = 3;    % duración mínima para reportar un episodio (días)

TOP_TABLA    = 30;   % episodios a mostrar en tabla consola
TOP_ZOOM     = 6;    % episodios para gráfica de zoom
TOP_RANKING  = 20;   % episodios para gráfica de ranking

MARGEN_ZOOM  = 10;   % días de contexto a cada lado del episodio en zoom

COLOR_RETIROS = [0.20 0.45 0.75];
COLOR_COMPRAS = [0.85 0.40 0.10];

%% ============================================================
%% 1. CARGA DE DATOS
%% ============================================================
load('AnalisisRetirosME.mat');

retiros_sf   = data_values(:, 2);
compras_mesa = data_values(:, 3);

tiene_fechas = exist('dates','var') && isa(dates,'datetime');
if tiene_fechas
    t = dates(:);
else
    t = (datetime('2000-01-01') + caldays(0:size(data_values,1)-1))';
    warning('Variable "dates" no encontrada. Se usó fecha sintética.');
end

n_obs  = numel(retiros_sf);
flujo  = retiros_sf + compras_mesa;   % flujo neto diario combinado

fprintf('============================================================\n');
fprintf('  ANÁLISIS DE EPISODIOS DE ESTRÉS — LIQUIDEZ\n');
fprintf('  Período  : %s  →  %s\n', datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
fprintf('  Obs      : %d  |  Gap tol.: %d d / %d d  |  Dur. min.: %d d\n', ...
    n_obs, GAP_1D, GAP_2D, MIN_DURACION);
fprintf('============================================================\n\n');

dias_neg = sum(flujo < 0);
fprintf('  Días con flujo negativo : %d  (%.1f%%)\n', dias_neg, dias_neg/n_obs*100);
fprintf('  Flujo medio (días neg.) : %.2f MM\n', mean(flujo(flujo<0)));
fprintf('  Peor día único          : %.2f MM  (%s)\n\n', min(flujo), ...
    datestr(t(flujo==min(flujo)),'dd-mmm-yyyy'));

%% ============================================================
%% 2. IDENTIFICACIÓN DE EPISODIOS
%% ============================================================
% Un día es "estrés" si el flujo combinado es negativo.
% Fusionamos días de estrés separados por ≤ gap_max días positivos.

function episodios = identificar_episodios(flujo, t, gap_max, min_dur)
    stress  = flujo < 0;

    % Dilatar máscara: absorber gaps de hasta gap_max días positivos
    stress_dil = stress;
    for g = 1:gap_max
        stress_dil(g+1:end) = stress_dil(g+1:end) | stress(1:end-g);
    end

    diff_s  = diff([0; stress_dil; 0]);
    inicios = find(diff_s ==  1);
    fines   = find(diff_s == -1) - 1;

    episodios = struct('inicio',{},'fin',{},'duracion',{},...
                       'flujo_acum',{},'flujo_neg_acum',{},...
                       'n_dias_neg',{},'peor_flujo',{},...
                       'fecha_ini',{},'fecha_fin',{},'fecha_peor',{});

    for e = 1:numel(inicios)
        seg = inicios(e):fines(e);

        % Recortar al primer y último día negativo real del bloque
        neg_en_seg = find(stress(seg));
        if isempty(neg_en_seg); continue; end
        ini_r = seg(neg_en_seg(1));
        fin_r = seg(neg_en_seg(end));
        seg_r = ini_r:fin_r;

        dur = fin_r - ini_r + 1;
        if dur < min_dur; continue; end

        fl_acum     = sum(flujo(seg_r));
        fl_neg_acum = sum(flujo(flujo(seg_r)<0));
        n_neg       = sum(flujo(seg_r) < 0);
        [pf, ip]    = min(flujo(seg_r));

        ep.inicio         = ini_r;
        ep.fin            = fin_r;
        ep.duracion       = dur;
        ep.flujo_acum     = fl_acum;
        ep.flujo_neg_acum = fl_neg_acum;
        ep.n_dias_neg     = n_neg;
        ep.peor_flujo     = pf;
        ep.fecha_ini      = t(ini_r);
        ep.fecha_fin      = t(fin_r);
        ep.fecha_peor     = t(ini_r + ip - 1);
        episodios(end+1)  = ep; %#ok<AGROW>
    end

    % Ordenar por flujo negativo acumulado (más negativo = más severo)
    if ~isempty(episodios)
        [~, ord]  = sort([episodios.flujo_neg_acum]);
        episodios = episodios(ord);
    end
end

tolerancias = [GAP_1D, GAP_2D];
etiq_tol    = {sprintf('gap %d día',  GAP_1D), sprintf('gap %d días', GAP_2D)};
resultados  = cell(2,1);

for ti = 1:2
    ep = identificar_episodios(flujo, t, tolerancias(ti), MIN_DURACION);
    resultados{ti} = ep;

    fprintf('=== EPISODIOS — %s ===\n', etiq_tol{ti});
    fprintf('  Total episodios (dur ≥ %dd): %d\n\n', MIN_DURACION, numel(ep));

    if isempty(ep); continue; end

    fprintf('%-4s  %-13s  %-13s  %5s  %5s  %11s  %11s  %13s  %-13s\n', ...
        'Rank','Inicio','Fin','Días','Neg.','FlNeto(MM)','FlNeg(MM)','Peor día(MM)','Fecha peor');
    fprintf('%s\n', repmat('-',1,100));
    for e = 1:min(TOP_TABLA, numel(ep))
        fprintf('%-4d  %-13s  %-13s  %5d  %5d  %11.1f  %11.1f  %13.1f  %-13s\n', e, ...
            datestr(ep(e).fecha_ini,'dd-mmm-yyyy'), datestr(ep(e).fecha_fin,'dd-mmm-yyyy'), ...
            ep(e).duracion, ep(e).n_dias_neg, ep(e).flujo_acum, ep(e).flujo_neg_acum, ...
            ep(e).peor_flujo, datestr(ep(e).fecha_peor,'dd-mmm-yyyy'));
    end
    fprintf('\n');
end

%% ============================================================
%% 3. GRÁFICAS  (usar gap 2 días para visualización)
%% ============================================================
ep_list = resultados{2};
n_ep    = numel(ep_list);

% --- Fig 1: Series apiladas ---
figure('Name','Series de Liquidez','Position',[30 30 1200 500]);
hold on;
b = bar(t, [retiros_sf, compras_mesa], 'stacked', 'EdgeColor','none');
b(1).FaceColor = COLOR_RETIROS;
b(2).FaceColor = COLOR_COMPRAS;
yline(0,'k-','LineWidth',0.8);
title('Retiros SF + Compras Netas Mesa — apiladas (MM)','FontWeight','bold');
ylabel('MM'); xlabel('Fecha');
legend({'Retiros SF','Compras Mesa'},'Location','best','FontSize',8);
grid on; box off;
sgtitle('Series de Liquidez — AnalisisRetirosME','FontSize',13,'FontWeight','bold');

% --- Fig 2: Flujo neto + episodios sombreados ---
figure('Name','Flujo Neto y Episodios','Position',[30 30 1300 500]);
hold on;

top_ep  = min(10, n_ep);
cmap_ep = turbo(top_ep + 2); cmap_ep = cmap_ep(2:end-1,:);
y_lim   = [min(flujo)*1.15, max(flujo)*1.15];

for e = 1:top_ep
    ep = ep_list(e);
    patch([ep.fecha_ini ep.fecha_fin ep.fecha_fin ep.fecha_ini], ...
          [y_lim(1) y_lim(1) y_lim(2) y_lim(2)], ...
          cmap_ep(e,:), 'FaceAlpha',0.18, 'EdgeColor', cmap_ep(e,:), 'LineWidth',0.5);
    text(ep.fecha_ini + (ep.fecha_fin-ep.fecha_ini)/2, y_lim(2)*0.92, ...
         sprintf('#%d',e), 'FontSize',8,'FontWeight','bold', ...
         'Color',cmap_ep(e,:)*0.65,'HorizontalAlignment','center');
end

bar(t, max(flujo,0), 'FaceColor',[0.3 0.65 0.3], 'EdgeColor','none','DisplayName','Positivo');
bar(t, min(flujo,0), 'FaceColor',[0.85 0.2 0.2], 'EdgeColor','none','DisplayName','Negativo');
yline(0,'k-','LineWidth',0.8);
ylim(y_lim);
legend('Location','best','FontSize',8);
ylabel('MM'); xlabel('Fecha');
title(sprintf('Flujo Neto Diario (Retiros SF + Compras Mesa) — Top %d Episodios de Estrés', top_ep), ...
    'FontWeight','bold');
grid on; box off;

% --- Fig 3: Zoom en los peores episodios ---
figure('Name','Zoom Episodios Críticos','Position',[30 30 1400 780]);
n_zoom = min(TOP_ZOOM, n_ep);
ncols  = 3; nrows = ceil(n_zoom/ncols);
tiledlayout(nrows, ncols, 'TileSpacing','compact','Padding','compact');

for e = 1:n_zoom
    ep    = ep_list(e);
    ini_v = max(1, ep.inicio - MARGEN_ZOOM);
    fin_v = min(n_obs, ep.fin   + MARGEN_ZOOM);
    seg_v = ini_v:fin_v;

    y_min = min([retiros_sf(seg_v); compras_mesa(seg_v)]) * 1.2;
    y_max = max([retiros_sf(seg_v); compras_mesa(seg_v)]) * 1.2;
    if y_min == y_max; y_max = y_min + 1; end

    nexttile; hold on;
    patch([ep.fecha_ini ep.fecha_fin ep.fecha_fin ep.fecha_ini], ...
          [y_min y_min y_max y_max],[1 0.75 0.75], ...
          'FaceAlpha',0.4,'EdgeColor',[0.8 0.3 0.3],'LineWidth',0.8,'HandleVisibility','off');
    bz = bar(t(seg_v), [retiros_sf(seg_v), compras_mesa(seg_v)], 'stacked', 'EdgeColor','none');
    bz(1).FaceColor = COLOR_RETIROS;
    bz(2).FaceColor = COLOR_COMPRAS;
    bz(1).DisplayName = 'Retiros SF';
    bz(2).DisplayName = 'Compras Mesa';
    yline(0,'k-','LineWidth',0.8);
    ylim([y_min y_max]);
    title(sprintf('#%d  %s → %s  (%dd)\nFlNeg: %.0f MM  |  Peor: %.0f MM (%s)', e, ...
        datestr(ep.fecha_ini,'dd-mmm-yy'), datestr(ep.fecha_fin,'dd-mmm-yy'), ep.duracion, ...
        ep.flujo_neg_acum, ep.peor_flujo, datestr(ep.fecha_peor,'dd-mmm-yy')), ...
        'FontSize',8,'FontWeight','bold');
    ylabel('MM'); grid on; box off;
    if e==1; legend('Location','best','FontSize',7); end
end
sgtitle(sprintf('Zoom — %d Peores Episodios de Estrés (gap ≤ %d días)', n_zoom, GAP_2D), ...
    'FontSize',13,'FontWeight','bold');

% --- Fig 4: Ranking horizontal ---
figure('Name','Ranking Episodios','Position',[30 30 980 650]);
top_r  = min(TOP_RANKING, n_ep);
fl_top = [ep_list(1:top_r).flujo_neg_acum];
labels = arrayfun(@(ep) sprintf('%s → %s  (%dd)', ...
    datestr(ep.fecha_ini,'dd-mmm-yy'), datestr(ep.fecha_fin,'dd-mmm-yy'), ep.duracion), ...
    ep_list(1:top_r), 'UniformOutput', false);

barh(top_r:-1:1, fl_top(end:-1:1), 'FaceColor',[0.85 0.2 0.2], 'EdgeColor','none');
set(gca,'YTick',1:top_r,'YTickLabel',flipud(labels),'FontSize',8);
xlabel('Flujo negativo acumulado en el episodio (MM)');
title(sprintf('Ranking — %d Peores Episodios de Estrés de Liquidez\n(gap ≤ %d días | ordenado por flujo neg. acumulado)', ...
    top_r, GAP_2D),'FontWeight','bold');
grid on; box off;

%% ============================================================
%% 4. RESUMEN FINAL EN CONSOLA
%% ============================================================
fprintf('\n');
fprintf('############################################################\n');
fprintf('##   EPISODIOS DE ESTRÉS — RESUMEN COMPLETO CON FECHAS   ##\n');
fprintf('##   Gap <= %d dias  |  Dur. min. %d dias                   ##\n', GAP_2D, MIN_DURACION);
fprintf('############################################################\n\n');

fprintf('%-4s  %-13s  %-13s  %5s  %5s  %11s  %11s  %13s  %-13s\n', ...
    'Rank','Inicio','Fin','Días','Neg.','FlNeto(MM)','FlNeg(MM)','Peor día(MM)','Fecha peor');
fprintf('%s\n', repmat('─',1,100));
for e = 1:n_ep
    ep = ep_list(e);
    fprintf('%-4d  %-13s  %-13s  %5d  %5d  %11.1f  %11.1f  %13.1f  %-13s\n', e, ...
        datestr(ep.fecha_ini,'dd-mmm-yyyy'), datestr(ep.fecha_fin,'dd-mmm-yyyy'), ...
        ep.duracion, ep.n_dias_neg, ep.flujo_acum, ep.flujo_neg_acum, ...
        ep.peor_flujo, datestr(ep.fecha_peor,'dd-mmm-yyyy'));
end
fprintf('\n  Total episodios identificados: %d\n', n_ep);
fprintf('  Período : %s → %s\n', datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
fprintf('\n  Columnas:\n');
fprintf('    Días     = duración total del episodio\n');
fprintf('    Neg.     = número de días con flujo negativo dentro del episodio\n');
fprintf('    FlNeto   = flujo neto acumulado (pos + neg) durante el episodio [MM]\n');
fprintf('    FlNeg    = solo días negativos acumulados durante el episodio [MM]\n');
fprintf('    Peor día = flujo del peor día individual dentro del episodio [MM]\n');
