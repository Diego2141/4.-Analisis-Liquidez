%% ANÁLISIS DE ESTRÉS — VENTANA RODANTE ACUMULADA
% Series analizadas:
%   - Retiros SF        (col 2): negativo = salida de liquidez
%   - Compras netas mesa (col 3): negativo = salida de liquidez
%
% Metodología: para cada tamaño de ventana (N días), se calcula la suma
% acumulada de flujos en cada ventana rodante. Las ventanas con suma más
% negativa son los peores episodios de estrés. Días positivos pequeños
% quedan diluidos dentro de la ventana y no rompen el episodio.

clc; clear; close all;

%% ============================================================
%% PARÁMETROS
%% ============================================================

% Tamaños de ventana a analizar (días hábiles)
VENTANAS     = [5, 10, 15, 20];   % 1, 2, 3 y 4 semanas

% Número de episodios no solapados a identificar por ventana
TOP_EP       = 20;

% Episodios a mostrar en zoom y ranking
TOP_ZOOM     = 6;
TOP_RANKING  = 15;

% Margen de contexto en zoom (días a cada lado)
MARGEN_ZOOM  = 5;

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

n_obs = numel(retiros_sf);
flujo = retiros_sf + compras_mesa;

fprintf('============================================================\n');
fprintf('  ANÁLISIS DE ESTRÉS — VENTANA RODANTE\n');
fprintf('  Período  : %s  →  %s\n', datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
fprintf('  Obs      : %d  |  Ventanas: %s días\n', n_obs, num2str(VENTANAS));
fprintf('============================================================\n\n');

%% ============================================================
%% 2. EPISODIOS POR VENTANA RODANTE
%% ============================================================
% Para cada ventana de N días: la suma rodante en el día i representa
% el flujo acumulado entre los días [i, i+N-1].
% Se seleccionan los TOP_EP peores episodios NO solapados
% usando un algoritmo greedy (el peor primero, luego se descarta
% todo lo que solapa con él, y se repite).

resultados = cell(numel(VENTANAS), 1);

for vi = 1:numel(VENTANAS)
    N = VENTANAS(vi);

    % Suma rodante: índice i = ventana [i : i+N-1]
    suma_rod = movsum(flujo, [0, N-1]);   % suma hacia adelante
    suma_rod(end-N+2:end) = NaN;          % descartar ventanas incompletas

    % Selección greedy de episodios no solapados
    episodios = struct('inicio',{},'fin',{},'suma',{},...
                       'fecha_ini',{},'fecha_fin',{},...
                       'peor_flujo',{},'fecha_peor',{});

    disponible = true(n_obs, 1);

    for e = 1:TOP_EP
        % Encontrar la ventana más negativa entre las disponibles
        suma_tmp = suma_rod;
        suma_tmp(~disponible) = NaN;
        [val_min, idx_min] = min(suma_tmp);

        if isnan(val_min) || val_min >= 0; break; end

        ini = idx_min;
        fin = min(n_obs, idx_min + N - 1);
        seg = ini:fin;

        [pf, ip] = min(flujo(seg));

        ep.inicio     = ini;
        ep.fin        = fin;
        ep.suma       = val_min;
        ep.fecha_ini  = t(ini);
        ep.fecha_fin  = t(fin);
        ep.peor_flujo = pf;
        ep.fecha_peor = t(ini + ip - 1);
        episodios(end+1) = ep; %#ok<AGROW>

        % Marcar como no disponibles todos los índices solapados
        bloquear_ini = max(1,   ini - N + 1);
        bloquear_fin = min(n_obs, fin);
        disponible(bloquear_ini:bloquear_fin) = false;
    end

    resultados{vi} = episodios;

    fprintf('=== VENTANA %d días (%d semanas) ===\n', N, N/5);
    fprintf('  Episodios encontrados: %d\n\n', numel(episodios));
    fprintf('%-4s  %-13s  %-13s  %14s  %14s  %-13s\n', ...
        'Rank','Inicio','Fin','Flujo acum.(MM)','Peor día(MM)','Fecha peor');
    fprintf('%s\n', repmat('-',1,75));
    for e = 1:numel(episodios)
        ep = episodios(e);
        fprintf('%-4d  %-13s  %-13s  %14.1f  %14.1f  %-13s\n', e, ...
            datestr(ep.fecha_ini,'dd-mmm-yyyy'), datestr(ep.fecha_fin,'dd-mmm-yyyy'), ...
            ep.suma, ep.peor_flujo, datestr(ep.fecha_peor,'dd-mmm-yyyy'));
    end
    fprintf('\n');
end

%% ============================================================
%% 3. GRÁFICAS
%% ============================================================

% --- Fig 1: Sumas rodantes para cada ventana ---
figure('Name','Sumas Rodantes','Position',[30 30 1300 700]);
tiledlayout(numel(VENTANAS), 1, 'TileSpacing','compact','Padding','compact');
for vi = 1:numel(VENTANAS)
    N = VENTANAS(vi);
    sr = movsum(flujo, [0, N-1]);
    sr(end-N+2:end) = NaN;
    nexttile; hold on;
    area(t, min(sr,0), 'FaceColor',[0.85 0.2 0.2],'FaceAlpha',0.6,'EdgeColor','none');
    area(t, max(sr,0), 'FaceColor',[0.3 0.65 0.3],'FaceAlpha',0.6,'EdgeColor','none');
    yline(0,'k-','LineWidth',0.8);
    title(sprintf('Suma rodante %d días (%d sem.)', N, N/5),'FontWeight','bold');
    ylabel('MM'); grid on; box off;
end
xlabel('Fecha');
sgtitle('Flujo Acumulado por Ventana Rodante (Retiros SF + Compras Mesa)', ...
    'FontSize',13,'FontWeight','bold');

% --- Figs 2-5: Zoom + Ranking por cada ventana ---
for vi = 1:numel(VENTANAS)
    N        = VENTANAS(vi);
    ep_list  = resultados{vi};
    n_ep     = numel(ep_list);
    if n_ep == 0; continue; end

    % Zoom
    figure('Name', sprintf('Zoom %dd', N), 'Position',[30 30 1400 750]);
    n_zoom = min(TOP_ZOOM, n_ep);
    ncols  = 3; nrows = ceil(n_zoom/ncols);
    tiledlayout(nrows, ncols,'TileSpacing','compact','Padding','compact');

    for e = 1:n_zoom
        ep    = ep_list(e);
        ini_v = max(1,     ep.inicio - MARGEN_ZOOM);
        fin_v = min(n_obs, ep.fin    + MARGEN_ZOOM);
        seg_v = ini_v:fin_v;

        % Calcular ylim sobre la ventana del episodio con apilado
        apilado = retiros_sf(seg_v) + compras_mesa(seg_v);
        y_min   = min([retiros_sf(seg_v); compras_mesa(seg_v); apilado]) * 1.25;
        y_max   = max([retiros_sf(seg_v); compras_mesa(seg_v); apilado]) * 1.25;
        if y_min == y_max; y_max = y_min + 1; end

        nexttile; hold on;
        set(gca, 'Color','white');

        % Área sombreada del episodio (gris claro + borde negro)
        patch([ep.fecha_ini ep.fecha_fin ep.fecha_fin ep.fecha_ini], ...
              [y_min y_min y_max y_max], [0.82 0.82 0.82], ...
              'FaceAlpha',0.45, 'EdgeColor',[0 0 0], 'LineWidth',1.8, 'HandleVisibility','off');

        % Retiros SF: gris oscuro sólido
        bz1 = bar(t(seg_v), retiros_sf(seg_v), 'FaceColor',[0.25 0.25 0.25], ...
                  'EdgeColor','none', 'DisplayName','Retiros SF');

        % Compras Mesa: blanco con borde negro (vacías, sobre las barras anteriores)
        bz2 = bar(t(seg_v), compras_mesa(seg_v), 'FaceColor',[1 1 1], ...
                  'EdgeColor',[0 0 0], 'LineWidth',0.6, 'DisplayName','Compras Mesa');

        % Línea negra gruesa del flujo total con marcadores
        plot(t(seg_v), flujo(seg_v), 'k-o', 'LineWidth',2, ...
             'MarkerSize',3, 'MarkerFaceColor','k', 'DisplayName','Total');

        yline(0,'k-','LineWidth',0.8,'HandleVisibility','off');
        ylim([y_min y_max]);
        title(sprintf('#%d  %s → %s\nAcum: %.0f MM  |  Peor: %.0f MM (%s)', e, ...
            datestr(ep.fecha_ini,'dd-mmm-yy'), datestr(ep.fecha_fin,'dd-mmm-yy'), ...
            ep.suma, ep.peor_flujo, datestr(ep.fecha_peor,'dd-mmm-yy')), ...
            'FontSize',8,'FontWeight','bold');
        ylabel('MM'); grid on; box off;
        if e==1; legend('Location','best','FontSize',7); end
    end
    sgtitle(sprintf('Zoom — %d Peores Episodios | Ventana %d días (%d sem.)', ...
        n_zoom, N, N/5),'FontSize',12,'FontWeight','bold');

    % Ranking
    figure('Name', sprintf('Ranking %dd', N), 'Position',[30 30 950 580]);
    top_r  = min(TOP_RANKING, n_ep);
    sumas  = [ep_list(1:top_r).suma];
    labels = arrayfun(@(ep) sprintf('%s → %s', ...
        datestr(ep.fecha_ini,'dd-mmm-yy'), datestr(ep.fecha_fin,'dd-mmm-yy')), ...
        ep_list(1:top_r), 'UniformOutput', false);
    sumas_flip = sumas(end:-1:1);
    barh(top_r:-1:1, sumas_flip, 'FaceColor',[0.85 0.2 0.2],'EdgeColor','none');
    set(gca,'YTick',1:top_r,'YTickLabel',flipud(labels),'FontSize',8);
    xlabel('Flujo acumulado en la ventana (MM)');
    title(sprintf('Ranking — Peores Episodios | Ventana %d días (%d sem.)', N, N/5), ...
        'FontWeight','bold');
    % Etiquetas de valor al extremo de cada barra
    for r = 1:top_r
        text(sumas_flip(r) - abs(min(sumas_flip))*0.01, r, ...
            sprintf(' %.0f MM', sumas_flip(r)), ...
            'HorizontalAlignment','right', 'VerticalAlignment','middle', ...
            'FontSize',7, 'FontWeight','bold', 'Color','white');
    end
    grid on; box off;
end

%% ============================================================
%% 4. RESUMEN FINAL EN CONSOLA
%% ============================================================
fprintf('\n############################################################\n');
fprintf('##   RESUMEN — PEORES EPISODIOS POR VENTANA (FECHAS)     ##\n');
fprintf('############################################################\n');
for vi = 1:numel(VENTANAS)
    N       = VENTANAS(vi);
    ep_list = resultados{vi};
    fprintf('\n--- Ventana %d días (%d semanas) ---\n', N, N/5);
    fprintf('%-4s  %-13s  %-13s  %14s  %14s  %-13s\n', ...
        'Rank','Inicio','Fin','Flujo acum.(MM)','Peor día(MM)','Fecha peor');
    fprintf('%s\n', repmat('-',1,75));
    for e = 1:numel(ep_list)
        ep = ep_list(e);
        fprintf('%-4d  %-13s  %-13s  %14.1f  %14.1f  %-13s\n', e, ...
            datestr(ep.fecha_ini,'dd-mmm-yyyy'), datestr(ep.fecha_fin,'dd-mmm-yyyy'), ...
            ep.suma, ep.peor_flujo, datestr(ep.fecha_peor,'dd-mmm-yyyy'));
    end
end

%% ============================================================
%% 5. GUARDAR FIGURAS EN JPG
%% ============================================================
carpeta_out = 'plots_estres';
if ~exist(carpeta_out, 'dir'); mkdir(carpeta_out); end

figs = findall(0, 'Type', 'figure');
fprintf('\nGuardando %d figuras en carpeta "%s"...\n', numel(figs), carpeta_out);
for f = 1:numel(figs)
    fig = figs(f);
    nombre = get(fig, 'Name');
    if isempty(nombre); nombre = sprintf('figura_%d', fig.Number); end
    nombre = strrep(nombre, ' ', '_');
    nombre = regexprep(nombre, '[^a-zA-Z0-9_-]', '');
    ruta   = fullfile(carpeta_out, sprintf('%02d_%s.jpg', fig.Number, nombre));
    exportgraphics(fig, ruta, 'Resolution', 200);
    fprintf('  Guardada: %s\n', ruta);
end
fprintf('Listo.\n');
