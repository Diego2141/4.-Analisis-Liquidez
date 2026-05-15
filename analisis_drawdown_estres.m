%% ANÁLISIS DE DRAWDOWN - Períodos de Estrés de Liquidez
% Series analizadas:
%   - Retiros SF       (col 2): negativo = salida de liquidez
%   - Compras netas mesa (col 3): negativo = salida de liquidez
%
% Metodología: drawdown sobre flujo negativo acumulado combinado.
% Un día positivo aislado no cierra el episodio de estrés salvo que
% sea suficientemente grande para recuperar el nivel previo.

clc; clear; close all;

%% 1. CARGA DE DATOS
load('AnalisisRetirosME.mat');

retiros_sf   = data_values(:, 2);   % Retiros SF        [MM]
compras_mesa = data_values(:, 3);   % Compras netas mesa [MM]

tiene_fechas = exist('dates','var') && isa(dates,'datetime');
if tiene_fechas
    t = dates(:);
else
    t = (datetime('2000-01-01') + caldays(0:size(data_values,1)-1))';
    warning('Variable "dates" no encontrada. Se usó fecha sintética desde 2000-01-01.');
end

n_obs = numel(retiros_sf);

fprintf('============================================================\n');
fprintf('  ANÁLISIS DE DRAWDOWN — ESTRÉS DE LIQUIDEZ\n');
fprintf('  Período : %s  →  %s\n', datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
fprintf('  Obs     : %d\n', n_obs);
fprintf('============================================================\n\n');

%% 2. FLUJO DE ESTRÉS DIARIO
% Solo la parte negativa de cada serie contribuye al estrés.
% La parte positiva reduce el estrés pero no se amplifica.
flujo_estres = min(retiros_sf, 0) + min(compras_mesa, 0);   % ≤ 0 siempre

% Flujo total observado (sin filtrar positivos) — para contexto
flujo_total  = retiros_sf + compras_mesa;

fprintf('--- FLUJO DE ESTRÉS DIARIO (MM) ---\n');
dias_estres = sum(flujo_estres < 0);
fprintf('  Días con estrés    : %d  (%.1f%% del total)\n', dias_estres, dias_estres/n_obs*100);
fprintf('  Flujo medio estrés : %.2f MM\n',  mean(flujo_estres(flujo_estres<0)));
fprintf('  Peor día           : %.2f MM  (%s)\n', min(flujo_estres), datestr(t(flujo_estres==min(flujo_estres)),'dd-mmm-yyyy'));

%% 3. DRAWDOWN ACUMULADO
% Acumulamos el flujo de estrés. El drawdown mide cuánto ha caído
% el nivel acumulado desde su último máximo.
cum_flujo   = cumsum(flujo_estres);
peak_run    = cummax(cum_flujo);           % máximo corrido
drawdown    = cum_flujo - peak_run;        % ≤ 0; profundidad del hoyo

fprintf('\n--- DRAWDOWN GLOBAL (MM acumulados) ---\n');
fprintf('  Máximo drawdown    : %.2f MM\n', min(drawdown));
fprintf('  Drawdown medio     : %.2f MM\n', mean(drawdown));
fprintf('  Días en drawdown   : %d  (%.1f%%)\n', sum(drawdown<0), sum(drawdown<0)/n_obs*100);

%% 4. IDENTIFICACIÓN DE EPISODIOS CON TOLERANCIA DE GAP
% Tolerancias probadas: 1 semana (5 días) y 2 semanas (10 días).
% Si entre dos períodos de drawdown negativo el gap es ≤ tolerancia,
% se fusionan en un solo episodio de estrés.

tolerancias  = [5, 10];
etiq_tol     = {'1 semana (5d)', '2 semanas (10d)'};
resultados   = cell(numel(tolerancias), 1);

for ti = 1:numel(tolerancias)
    gap_max = tolerancias(ti);

    % Máscara binaria de días en drawdown
    en_dd = drawdown < 0;

    % Dilatar la máscara: extender cada bloque "en estrés" gap_max días
    % hacia adelante para absorber gaps cortos positivos
    en_dd_dilatado = en_dd;
    for g = 1:gap_max
        en_dd_dilatado(g+1:end) = en_dd_dilatado(g+1:end) | en_dd(1:end-g);
    end

    % Encontrar inicio y fin de cada episodio fusionado
    diff_dd  = diff([0; en_dd_dilatado; 0]);
    inicios  = find(diff_dd ==  1);
    fines    = find(diff_dd == -1) - 1;
    n_ep     = numel(inicios);

    % Recortar cada episodio al rango real de drawdown (sin el padding)
    episodios = struct('inicio',{},'fin',{},'duracion',{},...
                       'flujo_acum',{},'max_dd',{},'peor_dia',{},...
                       'fecha_ini',{},'fecha_fin',{},'fecha_peor',{});

    for e = 1:n_ep
        idx   = inicios(e):fines(e);
        % Restringir al rango donde realmente hubo drawdown
        real  = idx(en_dd(idx));
        if isempty(real); continue; end
        ini_r = real(1); fin_r = real(end);
        seg   = ini_r:fin_r;

        ep.inicio     = ini_r;
        ep.fin        = fin_r;
        ep.duracion   = fin_r - ini_r + 1;         % días calendario del bloque
        ep.flujo_acum = sum(flujo_estres(seg));     % flujo negativo acumulado (MM)
        ep.max_dd     = min(drawdown(seg));         % profundidad máxima
        [~, ip]       = min(flujo_estres(seg));
        ep.peor_dia   = flujo_estres(ini_r + ip - 1);
        ep.fecha_ini  = t(ini_r);
        ep.fecha_fin  = t(fin_r);
        ep.fecha_peor = t(ini_r + ip - 1);
        episodios(end+1) = ep; %#ok<AGROW>
    end

    % Ordenar por flujo acumulado (más negativo = más severo)
    [~, ord] = sort([episodios.flujo_acum]);
    episodios = episodios(ord);
    resultados{ti} = episodios;

    fprintf('\n=== EPISODIOS — tolerancia gap %s ===\n', etiq_tol{ti});
    fprintf('  Total episodios identificados: %d\n\n', numel(episodios));
    fprintf('%-4s  %-13s  %-13s  %8s  %12s  %10s  %13s\n', ...
        'Rank','Inicio','Fin','Días','Flujo(MM)','MaxDD(MM)','Peor día(MM)');
    fprintf('%s\n', repmat('-',1,80));
    top_n = min(20, numel(episodios));
    for e = 1:top_n
        ep = episodios(e);
        fprintf('%-4d  %-13s  %-13s  %8d  %12.1f  %10.1f  %13.1f\n', e, ...
            datestr(ep.fecha_ini,'dd-mmm-yyyy'), datestr(ep.fecha_fin,'dd-mmm-yyyy'), ...
            ep.duracion, ep.flujo_acum, ep.max_dd, ep.peor_dia);
    end
end

%% 5. GRÁFICAS
colores = [0.2 0.5 0.8;   % azul  — Retiros SF
           0.8 0.4 0.1];  % naranja — Compras mesa

% --- Fig 1: Series crudas + flujo combinado ---
figure('Name','Series y Flujo de Estrés','Position',[50 50 1200 700]);
tiledlayout(3,1,'TileSpacing','compact');

nexttile;
bar(t, retiros_sf, 'FaceColor', colores(1,:), 'EdgeColor','none');
yline(0,'k-','LineWidth',0.8);
title('Retiros SF (MM)', 'FontWeight','bold');
ylabel('MM'); grid on; box off;

nexttile;
bar(t, compras_mesa, 'FaceColor', colores(2,:), 'EdgeColor','none');
yline(0,'k-','LineWidth',0.8);
title('Compras Netas Mesa (MM)', 'FontWeight','bold');
ylabel('MM'); grid on; box off;

nexttile;
area(t, flujo_estres, 'FaceColor',[0.85 0.2 0.2], 'FaceAlpha',0.6, 'EdgeColor','none');
yline(0,'k-','LineWidth',0.8);
title('Flujo de Estrés Combinado — solo componente negativa (MM)', 'FontWeight','bold');
ylabel('MM'); xlabel('Fecha'); grid on; box off;

sgtitle('Series de Liquidez — AnalisisRetirosME', 'FontSize',13,'FontWeight','bold');

% --- Fig 2: Drawdown acumulado + episodios (tolerancia 2 semanas) ---
figure('Name','Drawdown y Episodios de Estrés','Position',[50 50 1300 600]);
ep_list = resultados{2};   % usar tolerancia de 2 semanas para la visualización
top_ep  = min(10, numel(ep_list));

ax = axes; hold on;
% Sombrear los 10 peores episodios
cmap_ep = winter(top_ep);
for e = 1:top_ep
    ep = ep_list(e);
    patch([ep.fecha_ini ep.fecha_fin ep.fecha_fin ep.fecha_ini], ...
          [min(drawdown)*1.05 min(drawdown)*1.05 0 0], ...
          cmap_ep(e,:), 'FaceAlpha', 0.3, 'EdgeColor','none');
    text(ep.fecha_ini, min(drawdown)*1.02*(1 - 0.07*(e-1)), ...
         sprintf('#%d',e), 'FontSize',7, 'Color', cmap_ep(e,:)*0.7);
end
plot(t, drawdown, 'Color',[0.15 0.15 0.15], 'LineWidth', 1);
yline(0,'k-','LineWidth',0.8);
title('Drawdown Acumulado de Liquidez — Top 10 Episodios de Estrés (tolerancia 2 sem.)', ...
      'FontWeight','bold');
ylabel('MM acumulados'); xlabel('Fecha');
grid on; box off;
sgtitle('Análisis de Estrés de Liquidez — AnalisisRetirosME', 'FontSize',13,'FontWeight','bold');

% --- Fig 3: Zoom en los 5 peores episodios (subplots) ---
figure('Name','Zoom Episodios Críticos','Position',[50 50 1400 800]);
tiledlayout(2,3,'TileSpacing','compact');
for e = 1:min(5, numel(ep_list))
    ep = ep_list(e);
    % Ventana con margen de 20 días a cada lado
    ini_v = max(1, ep.inicio - 20);
    fin_v = min(n_obs, ep.fin + 20);
    seg_v = ini_v:fin_v;

    nexttile; hold on;
    bar(t(seg_v), retiros_sf(seg_v),   'FaceColor', colores(1,:), 'EdgeColor','none','DisplayName','Retiros SF');
    bar(t(seg_v), compras_mesa(seg_v), 'FaceColor', colores(2,:), 'EdgeColor','none','DisplayName','Compras Mesa');
    patch([ep.fecha_ini ep.fecha_fin ep.fecha_fin ep.fecha_ini], ...
          [min([retiros_sf(seg_v);compras_mesa(seg_v)])*1.1 ...
           min([retiros_sf(seg_v);compras_mesa(seg_v)])*1.1 ...
           max([retiros_sf(seg_v);compras_mesa(seg_v)])*1.1 ...
           max([retiros_sf(seg_v);compras_mesa(seg_v)])*1.1], ...
          [1 0.8 0.8], 'FaceAlpha',0.25,'EdgeColor','none','HandleVisibility','off');
    yline(0,'k-');
    title(sprintf('#%d  %s → %s\nFlujo: %.0f MM  |  %d días', e, ...
        datestr(ep.fecha_ini,'mmm-yyyy'), datestr(ep.fecha_fin,'mmm-yyyy'), ...
        ep.flujo_acum, ep.duracion), 'FontSize',9,'FontWeight','bold');
    ylabel('MM'); grid on; box off;
    if e == 1; legend('Location','best','FontSize',7); end
end
sgtitle('Zoom — 5 Peores Episodios de Estrés de Liquidez', 'FontSize',13,'FontWeight','bold');

% --- Fig 4: Ranking de episodios (barras horizontales) ---
figure('Name','Ranking Episodios','Position',[50 50 900 600]);
top_r = min(15, numel(ep_list));
flujos_top = [ep_list(1:top_r).flujo_acum];
labels_top = arrayfun(@(e) sprintf('%s\n→%s', ...
    datestr(e.fecha_ini,'mmm-yy'), datestr(e.fecha_fin,'mmm-yy')), ...
    ep_list(1:top_r), 'UniformOutput', false);
barh(top_r:-1:1, flujos_top(end:-1:1), 'FaceColor',[0.85 0.2 0.2], 'EdgeColor','none');
set(gca,'YTick',1:top_r,'YTickLabel',flipud(labels_top),'FontSize',8);
xlabel('Flujo negativo acumulado (MM)');
title(sprintf('Ranking de los %d Peores Episodios de Estrés de Liquidez\n(tolerancia gap 2 semanas)', top_r), ...
    'FontWeight','bold');
grid on; box off;

fprintf('\n============================================================\n');
fprintf('  Análisis completado. Figuras generadas: 4\n');
fprintf('  Top episodio: %s → %s  (%.1f MM  en %d días)\n', ...
    datestr(ep_list(1).fecha_ini,'dd-mmm-yyyy'), ...
    datestr(ep_list(1).fecha_fin,'dd-mmm-yyyy'), ...
    ep_list(1).flujo_acum, ep_list(1).duracion);
fprintf('============================================================\n');
