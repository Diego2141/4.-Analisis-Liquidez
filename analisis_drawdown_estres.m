%% ANÁLISIS DE DRAWDOWN - Períodos de Estrés de Liquidez
% Series analizadas:
%   - Retiros SF        (col 2): negativo = salida de liquidez
%   - Compras netas mesa (col 3): negativo = salida de liquidez
%
% Metodología: drawdown sobre flujo TOTAL combinado (positivo + negativo).
% Los días positivos reducen genuinamente el drawdown; un día positivo
% pequeño no cierra el episodio salvo que sea suficientemente grande
% para recuperar el nivel previo.

clc; clear; close all;

%% ============================================================
%% PARÁMETROS — modificar aquí
%% ============================================================

% Tolerancias de gap entre episodios (días hábiles)
GAP_1SEM   = 5;    % 1 semana
GAP_2SEM   = 10;   % 2 semanas

% Duración mínima de un episodio para ser reportado (días)
MIN_DURACION = 3;

% Número de episodios a mostrar en tabla consola
TOP_TABLA = 20;

% Número de episodios en gráfica de zoom y ranking
TOP_ZOOM    = 5;
TOP_RANKING = 15;

% Margen de contexto en gráficas de zoom (días a cada lado del episodio)
MARGEN_ZOOM = 20;

% Colores de series
COLOR_RETIROS = [0.20 0.45 0.75];   % azul
COLOR_COMPRAS = [0.85 0.40 0.10];   % naranja

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

n_obs = numel(retiros_sf);

fprintf('============================================================\n');
fprintf('  ANÁLISIS DE DRAWDOWN — ESTRÉS DE LIQUIDEZ\n');
fprintf('  Período  : %s  →  %s\n', datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
fprintf('  Obs      : %d\n', n_obs);
fprintf('  Gap tol. : %d d (1 sem)  /  %d d (2 sem)\n', GAP_1SEM, GAP_2SEM);
fprintf('============================================================\n\n');

%% ============================================================
%% 2. FLUJO COMBINADO Y DRAWDOWN
%% ============================================================
% Flujo total: suma de ambas series (positivos y negativos incluidos).
% Los días positivos genuinamente recuperan liquidez y pueden cerrar episodios.
flujo = retiros_sf + compras_mesa;

% Drawdown sobre el flujo acumulado
cum_flujo  = cumsum(flujo);
peak_run   = cummax(cum_flujo);
drawdown   = cum_flujo - peak_run;    % ≤ 0; 0 = nivel máximo histórico

% Flujo de estrés puro (solo componente negativa) — para estadísticas y Fig 1
flujo_neg = min(retiros_sf, 0) + min(compras_mesa, 0);

dias_neg = sum(flujo < 0);
fprintf('--- FLUJO COMBINADO DIARIO (MM) ---\n');
fprintf('  Días con flujo negativo : %d  (%.1f%%)\n', dias_neg, dias_neg/n_obs*100);
fprintf('  Flujo medio (días neg.) : %.2f MM\n', mean(flujo(flujo<0)));
fprintf('  Peor día                : %.2f MM  (%s)\n', min(flujo), ...
    datestr(t(flujo==min(flujo)),'dd-mmm-yyyy'));

fprintf('\n--- DRAWDOWN ACUMULADO (MM) ---\n');
fprintf('  Drawdown máximo : %.2f MM\n', min(drawdown));
fprintf('  Drawdown medio  : %.2f MM\n', mean(drawdown(drawdown<0)));
fprintf('  Días en DD < 0  : %d  (%.1f%%)\n', sum(drawdown<0), sum(drawdown<0)/n_obs*100);

%% ============================================================
%% 3. IDENTIFICACIÓN DE EPISODIOS
%% ============================================================
% Un episodio es un período continuo de drawdown < 0.
% Gaps ≤ tolerancia entre episodios se fusionan en uno solo.

tolerancias = [GAP_1SEM, GAP_2SEM];
etiq_tol    = {sprintf('1 sem (%dd)', GAP_1SEM), sprintf('2 sem (%dd)', GAP_2SEM)};
resultados  = cell(2, 1);

for ti = 1:2
    gap_max  = tolerancias(ti);
    en_dd    = drawdown < 0;

    % Dilatar máscara hacia adelante para absorber gaps cortos
    en_dd_dil = en_dd;
    for g = 1:gap_max
        en_dd_dil(g+1:end) = en_dd_dil(g+1:end) | en_dd(1:end-g);
    end

    diff_dd = diff([0; en_dd_dil; 0]);
    inicios = find(diff_dd ==  1);
    fines   = find(diff_dd == -1) - 1;

    episodios = struct('inicio',{},'fin',{},'duracion',{},...
                       'flujo_acum',{},'flujo_neg_acum',{},...
                       'max_dd',{},'peor_dia',{},...
                       'fecha_ini',{},'fecha_fin',{},'fecha_peor',{});

    for e = 1:numel(inicios)
        idx  = inicios(e):fines(e);
        real = idx(en_dd(idx));
        if isempty(real); continue; end
        ini_r = real(1); fin_r = real(end);
        seg   = ini_r:fin_r;

        dur = fin_r - ini_r + 1;
        if dur < MIN_DURACION; continue; end

        [~, ip] = min(flujo(seg));

        ep.inicio          = ini_r;
        ep.fin             = fin_r;
        ep.duracion        = dur;
        ep.flujo_acum      = sum(flujo(seg));        % flujo neto total (MM)
        ep.flujo_neg_acum  = sum(flujo_neg(seg));    % componente negativa pura (MM)
        ep.max_dd          = min(drawdown(seg));
        ep.peor_dia        = flujo(ini_r + ip - 1);
        ep.fecha_ini       = t(ini_r);
        ep.fecha_fin       = t(fin_r);
        ep.fecha_peor      = t(ini_r + ip - 1);
        episodios(end+1)   = ep; %#ok<AGROW>
    end

    % Ordenar por drawdown máximo (hoyo más profundo = más severo)
    [~, ord] = sort([episodios.max_dd]);
    episodios = episodios(ord);
    resultados{ti} = episodios;

    fprintf('\n=== EPISODIOS — tolerancia %s ===\n', etiq_tol{ti});
    fprintf('  Total episodios (dur ≥ %dd) : %d\n\n', MIN_DURACION, numel(episodios));
    fprintf('%-4s  %-13s  %-13s  %6s  %11s  %11s  %10s  %13s\n', ...
        'Rank','Inicio','Fin','Días','Flujo neto','Flujo neg.','MaxDD(MM)','Peor día(MM)');
    fprintf('%s\n', repmat('-',1,88));
    for e = 1:min(TOP_TABLA, numel(episodios))
        ep = episodios(e);
        fprintf('%-4d  %-13s  %-13s  %6d  %11.1f  %11.1f  %10.1f  %13.1f\n', e, ...
            datestr(ep.fecha_ini,'dd-mmm-yyyy'), datestr(ep.fecha_fin,'dd-mmm-yyyy'), ...
            ep.duracion, ep.flujo_acum, ep.flujo_neg_acum, ep.max_dd, ep.peor_dia);
    end
end

%% ============================================================
%% 4. GRÁFICAS
%% ============================================================
ep_list = resultados{2};   % tolerancia 2 semanas para visualización
n_ep    = numel(ep_list);

% --- Fig 1: Series crudas + flujo neto combinado ---
figure('Name','Series y Flujo','Position',[30 30 1200 680]);
tiledlayout(3,1,'TileSpacing','compact','Padding','compact');

nexttile;
bar(t, retiros_sf, 'FaceColor', COLOR_RETIROS, 'EdgeColor','none');
yline(0,'k-','LineWidth',0.8);
title('Retiros SF (MM)','FontWeight','bold');
ylabel('MM'); grid on; box off;

nexttile;
bar(t, compras_mesa, 'FaceColor', COLOR_COMPRAS, 'EdgeColor','none');
yline(0,'k-','LineWidth',0.8);
title('Compras Netas Mesa (MM)','FontWeight','bold');
ylabel('MM'); grid on; box off;

nexttile;
hold on;
pos_mask = flujo >= 0;
neg_mask = flujo < 0;
bar(t(pos_mask), flujo(pos_mask), 'FaceColor',[0.3 0.7 0.3], 'EdgeColor','none','DisplayName','Flujo positivo');
bar(t(neg_mask), flujo(neg_mask), 'FaceColor',[0.85 0.2 0.2], 'EdgeColor','none','DisplayName','Flujo negativo');
yline(0,'k-','LineWidth',0.8);
title('Flujo Neto Combinado (Retiros SF + Compras Mesa)','FontWeight','bold');
ylabel('MM'); xlabel('Fecha'); legend('Location','best','FontSize',8); grid on; box off;

sgtitle('Series de Liquidez — AnalisisRetirosME','FontSize',13,'FontWeight','bold');

% --- Fig 2: Drawdown acumulado + episodios sombreados ---
figure('Name','Drawdown Acumulado','Position',[30 30 1300 550]);
ax = axes; hold on;

top_ep  = min(10, n_ep);
cmap_ep = turbo(top_ep + 2);
cmap_ep = cmap_ep(2:end-1,:);

dd_min = min(drawdown) * 1.08;
for e = 1:top_ep
    ep = ep_list(e);
    patch([ep.fecha_ini ep.fecha_fin ep.fecha_fin ep.fecha_ini], ...
          [dd_min dd_min 0 0], cmap_ep(e,:), 'FaceAlpha',0.25,'EdgeColor','none');
    % Etiqueta en la parte superior del sombreado
    text(ep.fecha_ini + (ep.fecha_fin - ep.fecha_ini)/2, dd_min*0.05, ...
         sprintf('#%d',e), 'FontSize',8,'FontWeight','bold', ...
         'Color', cmap_ep(e,:)*0.7, 'HorizontalAlignment','center');
end

plot(t, drawdown, 'Color',[0.1 0.1 0.1], 'LineWidth',1);
yline(0,'k-','LineWidth',0.8);
ylim([dd_min 0]);
ylabel('MM acumulados'); xlabel('Fecha');
title(sprintf('Drawdown Acumulado de Liquidez — Top %d Episodios de Estrés (gap ≤ 2 sem.)', top_ep), ...
    'FontWeight','bold');
grid on; box off;

% --- Fig 3: Zoom en los peores episodios ---
figure('Name','Zoom Episodios Críticos','Position',[30 30 1400 780]);
n_zoom = min(TOP_ZOOM, n_ep);
ncols  = min(3, n_zoom);
nrows  = ceil(n_zoom / ncols);
tiledlayout(nrows, ncols, 'TileSpacing','compact','Padding','compact');

for e = 1:n_zoom
    ep    = ep_list(e);
    ini_v = max(1, ep.inicio - MARGEN_ZOOM);
    fin_v = min(n_obs, ep.fin + MARGEN_ZOOM);
    seg_v = ini_v:fin_v;

    y_min = min([retiros_sf(seg_v); compras_mesa(seg_v)]) * 1.15;
    y_max = max([retiros_sf(seg_v); compras_mesa(seg_v)]) * 1.15;
    if y_min == y_max; y_max = y_min + 1; end

    nexttile; hold on;
    % Sombrear período del episodio
    patch([ep.fecha_ini ep.fecha_fin ep.fecha_fin ep.fecha_ini], ...
          [y_min y_min y_max y_max], [1 0.8 0.8], ...
          'FaceAlpha',0.35,'EdgeColor','none','HandleVisibility','off');
    bar(t(seg_v), retiros_sf(seg_v),   'FaceColor',COLOR_RETIROS,'EdgeColor','none','DisplayName','Retiros SF');
    bar(t(seg_v), compras_mesa(seg_v), 'FaceColor',COLOR_COMPRAS,'EdgeColor','none','DisplayName','Compras Mesa');
    yline(0,'k-','LineWidth',0.8);
    ylim([y_min y_max]);
    title(sprintf('#%d  %s → %s\nFlNeto: %.0f MM  |  FlNeg: %.0f MM  |  %d días', e, ...
        datestr(ep.fecha_ini,'dd-mmm-yy'), datestr(ep.fecha_fin,'dd-mmm-yy'), ...
        ep.flujo_acum, ep.flujo_neg_acum, ep.duracion), 'FontSize',8,'FontWeight','bold');
    ylabel('MM'); grid on; box off;
    if e == 1; legend('Location','best','FontSize',7); end
end
sgtitle(sprintf('Zoom — %d Peores Episodios de Estrés (gap ≤ 2 sem.)', n_zoom), ...
    'FontSize',13,'FontWeight','bold');

% --- Fig 4: Ranking horizontal ---
figure('Name','Ranking Episodios','Position',[30 30 950 620]);
top_r  = min(TOP_RANKING, n_ep);
dd_top = [ep_list(1:top_r).max_dd];
labels = arrayfun(@(ep) sprintf('%s → %s  (%dd)', ...
    datestr(ep.fecha_ini,'mmm-yy'), datestr(ep.fecha_fin,'mmm-yy'), ep.duracion), ...
    ep_list(1:top_r), 'UniformOutput', false);

barh(top_r:-1:1, dd_top(end:-1:1), 'FaceColor',[0.85 0.2 0.2], 'EdgeColor','none');
set(gca,'YTick',1:top_r,'YTickLabel',flipud(labels),'FontSize',8);
xlabel('Drawdown máximo (MM acumulados)');
title(sprintf('Ranking — %d Peores Episodios de Estrés de Liquidez\n(ordenado por profundidad de drawdown, gap ≤ 2 sem.)', top_r), ...
    'FontWeight','bold');
grid on; box off;

fprintf('\n============================================================\n');
fprintf('  Análisis completado. Figuras generadas: 4\n');
fprintf('============================================================\n');

%% ============================================================
%% 5. RESUMEN FINAL DE EPISODIOS CON FECHAS
%% ============================================================
fprintf('\n\n');
fprintf('############################################################\n');
fprintf('##  EPISODIOS DE ESTRÉS IDENTIFICADOS — FECHAS EXACTAS   ##\n');
fprintf('##  (tolerancia gap 2 semanas | dur. mín. %d días)        ##\n', MIN_DURACION);
fprintf('############################################################\n\n');

fprintf('%-4s  %-16s  %-16s  %6s  %12s  %12s  %12s  %-14s\n', ...
    'Rank','Inicio','Fin','Días','Flujo neto','Flujo neg.','MaxDD','Peor fecha');
fprintf('%s\n', repmat('─',1,100));

for e = 1:n_ep
    ep = ep_list(e);
    fprintf('%-4d  %-16s  %-16s  %6d  %12.1f  %12.1f  %12.1f  %-14s\n', e, ...
        datestr(ep.fecha_ini,'dd-mmm-yyyy'), ...
        datestr(ep.fecha_fin,'dd-mmm-yyyy'), ...
        ep.duracion, ...
        ep.flujo_acum, ...
        ep.flujo_neg_acum, ...
        ep.max_dd, ...
        datestr(ep.fecha_peor,'dd-mmm-yyyy'));
end

fprintf('\n  Columnas:\n');
fprintf('    Flujo neto  = suma diaria (Retiros SF + Compras Mesa) durante el episodio [MM]\n');
fprintf('    Flujo neg.  = solo componente negativa acumulada durante el episodio [MM]\n');
fprintf('    MaxDD       = profundidad máxima del drawdown dentro del episodio [MM]\n');
fprintf('    Peor fecha  = fecha del día con el peor flujo diario\n');
fprintf('\n  Total episodios: %d\n', n_ep);
fprintf('  Período cubierto: %s → %s\n', ...
    datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
