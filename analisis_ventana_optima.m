%% ANÁLISIS DE VENTANA ÓPTIMA Y PEOR EPISODIO HISTÓRICO
% Metodología:
%   1. BARRIDO DE VENTANAS (N=1..MAX_N): para cada tamaño N, calcula la suma
%      rodante más negativa. La curva worst(N) vs N revela el tamaño de ventana
%      que concentra el máximo estrés ("codo" natural).
%
%   2. ALGORITMO DE KADANE (mínimo subarray): encuentra el peor período
%      contiguo de cualquier longitud sin restricciones de ventana.
%
% Serie analizada: flujo = Retiros SF + Compras netas mesa
%                  (negativo = salida de liquidez)

clc; clear; close all;

%% ============================================================
%% PARÁMETROS
%% ============================================================
% MAX_N se calcula automáticamente a partir del tamaño de la serie
MARGEN_ZOOM  = 10;    % días de contexto a cada lado en zoom Kadane

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
MAX_N = n_obs - 1;   % sin límite superior: barre todas las ventanas posibles

fprintf('============================================================\n');
fprintf('  ANÁLISIS DE VENTANA ÓPTIMA\n');
fprintf('  Período  : %s  →  %s\n', datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
fprintf('  Obs      : %d  |  Barrido N = 1..%d días hábiles\n', n_obs, MAX_N);
fprintf('============================================================\n\n');

%% ============================================================
%% 2. BARRIDO DE VENTANAS N=1..MAX_N
%% ============================================================
% Para cada N: peor suma rodante, y su posición (inicio de ventana)
worst_sum  = zeros(MAX_N, 1);
worst_idx  = zeros(MAX_N, 1);   % índice de inicio de la peor ventana

for N = 1:MAX_N
    sr = movsum(flujo, [0, N-1]);
    sr(end-N+2:end) = NaN;
    [worst_sum(N), worst_idx(N)] = min(sr);
end

% Normalizar por longitud de ventana: peor suma por día
worst_per_day = worst_sum ./ (1:MAX_N)';

% Encontrar el N que produce la peor suma total (mínimo global)
[~, N_opt_total] = min(worst_sum);

% Encontrar el N con mayor "eficiencia" de estrés (peor suma/día mínima)
[~, N_opt_perday] = min(worst_per_day);

fprintf('--- BARRIDO DE VENTANAS ---\n');
fprintf('  N con peor suma total   : %d días hábiles  →  %.1f MM\n', ...
    N_opt_total, worst_sum(N_opt_total));
fprintf('  N con peor suma/día     : %d días hábiles  →  %.2f MM/día\n\n', ...
    N_opt_perday, worst_per_day(N_opt_perday));

% Detalle del top-10 ventanas por suma total
fprintf('  Top 10 ventanas por suma acumulada:\n');
fprintf('  %4s  %12s  %13s  %13s  %12s\n', 'N','Suma(MM)','Inicio','Fin','Suma/día');
fprintf('  %s\n', repmat('-',1,58));
[sums_sorted, ord_n] = sort(worst_sum);
for k = 1:10
    N_k   = ord_n(k);
    ini_k = worst_idx(N_k);
    fin_k = min(n_obs, ini_k + N_k - 1);
    fprintf('  %4d  %12.1f  %-13s  %-13s  %12.2f\n', N_k, sums_sorted(k), ...
        datestr(t(ini_k),'dd-mmm-yyyy'), datestr(t(fin_k),'dd-mmm-yyyy'), ...
        sums_sorted(k)/N_k);
end

%% ============================================================
%% 3. ALGORITMO DE KADANE (peor subarray contiguo)
%% ============================================================
% Versión mínima de Kadane: encuentra el subarray de suma mínima (más negativa)
% Complejidad O(n). No requiere especificar longitud de ventana.

min_ending_here = 0;
min_so_far      = 0;
ini_tmp         = 1;
kad_ini         = 1;
kad_fin         = 1;

for i = 1:n_obs
    min_ending_here = min_ending_here + flujo(i);
    if min_ending_here < min_so_far
        min_so_far = min_ending_here;
        kad_fin    = i;
        kad_ini    = ini_tmp;
    end
    if min_ending_here > 0
        min_ending_here = 0;
        ini_tmp = i + 1;
    end
end

kad_dur      = kad_fin - kad_ini + 1;
kad_flujo    = sum(flujo(kad_ini:kad_fin));
kad_neg_acum = sum(flujo(flujo(kad_ini:kad_fin) < 0));
[kad_peor_v, kad_peor_i] = min(flujo(kad_ini:kad_fin));
kad_peor_fecha = t(kad_ini + kad_peor_i - 1);

fprintf('\n--- ALGORITMO DE KADANE (peor período contiguo sin restricción) ---\n');
fprintf('  Inicio          : %s\n', datestr(t(kad_ini),'dd-mmm-yyyy'));
fprintf('  Fin             : %s\n', datestr(t(kad_fin),'dd-mmm-yyyy'));
fprintf('  Duración        : %d días hábiles\n', kad_dur);
fprintf('  Flujo neto acum.: %.1f MM\n', kad_flujo);
fprintf('  Flujo neg. acum.: %.1f MM\n', kad_neg_acum);
fprintf('  Peor día        : %.1f MM  (%s)\n\n', kad_peor_v, ...
    datestr(kad_peor_fecha,'dd-mmm-yyyy'));

%% ============================================================
%% 4. GRÁFICAS
%% ============================================================

% --- Fig 1: Curva worst_sum(N) vs N  [suma total] ---
figure('Name','Barrido Ventanas - Suma Total','Position',[30 30 900 480]);
subplot(2,1,1);
plot(1:MAX_N, worst_sum, 'b-o', 'LineWidth',1.8, 'MarkerSize',4, 'MarkerFaceColor','b');
hold on;
xline(N_opt_total, 'r--', 'LineWidth',1.4, ...
    'Label', sprintf('N=%d (peor suma)', N_opt_total), 'LabelVerticalAlignment','bottom');
ylabel('Peor suma rodante (MM)','FontSize',10);
xlabel('Tamaño de ventana N (días hábiles)','FontSize',10);
title('Peor suma acumulada por tamaño de ventana N','FontWeight','bold','FontSize',11);
grid on; box off; set(gca,'FontSize',9);

subplot(2,1,2);
plot(1:MAX_N, worst_per_day, 'k-s', 'LineWidth',1.8, 'MarkerSize',4, 'MarkerFaceColor','k');
hold on;
xline(N_opt_perday, 'r--', 'LineWidth',1.4, ...
    'Label', sprintf('N=%d (peor/día)', N_opt_perday), 'LabelVerticalAlignment','bottom');
ylabel('Peor suma / día (MM)','FontSize',10);
xlabel('Tamaño de ventana N (días hábiles)','FontSize',10);
title('Estrés por día según tamaño de ventana N','FontWeight','bold','FontSize',11);
grid on; box off; set(gca,'FontSize',9);
sgtitle('Barrido de Ventanas — AnalisisRetirosME','FontSize',13,'FontWeight','bold');

% --- Fig 2: Heatmap de peores ventanas para N seleccionados ---
N_sel = [1 2 3 5 10 15 20 30 60 90 120 180 250 500 1000 MAX_N];
N_sel = unique(N_sel(N_sel <= MAX_N));
N_sel = N_sel(N_sel <= MAX_N);
figure('Name','Barrido Ventanas - Detalle','Position',[30 30 1300 600]);
hold on;
colores = cool(numel(N_sel));
for ki = 1:numel(N_sel)
    N_k   = N_sel(ki);
    ini_k = worst_idx(N_k);
    fin_k = min(n_obs, ini_k + N_k - 1);
    yv    = worst_sum(N_k);
    patch([t(ini_k) t(fin_k) t(fin_k) t(ini_k)], ...
          [0 0 yv yv], colores(ki,:), ...
          'FaceAlpha',0.35, 'EdgeColor',colores(ki,:)*0.6, 'LineWidth',1.5, ...
          'DisplayName', sprintf('N=%d (%s)', N_k, datestr(t(ini_k),'mmm-yy')));
end
yline(0,'k-','LineWidth',0.8);
legend('Location','best','FontSize',8,'NumColumns',3);
ylabel('Flujo acumulado (MM)','FontSize',10);
xlabel('Fecha','FontSize',10);
title({'Episodios Óptimos por Ventana — AnalisisRetirosME', ...
       'Peor episodio para cada tamaño de ventana N seleccionado'}, ...
      'FontSize',12,'FontWeight','bold');
grid on; box off; set(gca,'FontSize',9);

% --- Fig 3: Zoom Kadane — período completo ---
figure('Name','Kadane - Peor Episodio Historico','Position',[30 30 1300 550]);
ini_v = max(1,     kad_ini - MARGEN_ZOOM);
fin_v = min(n_obs, kad_fin + MARGEN_ZOOM);
seg_v = ini_v:fin_v;

y_min_k = min([retiros_sf(seg_v); compras_mesa(seg_v)]) * 1.25;
y_max_k = max([retiros_sf(seg_v); compras_mesa(seg_v)]) * 1.25;
if y_min_k == y_max_k; y_max_k = y_min_k + 1; end

hold on;
% Sombreado episodio
patch([t(kad_ini) t(kad_fin) t(kad_fin) t(kad_ini)], ...
      [y_min_k y_min_k y_max_k y_max_k], [0.82 0.82 0.82], ...
      'FaceAlpha',0.45, 'EdgeColor',[0 0 0], 'LineWidth',2, 'HandleVisibility','off');

% Retiros SF: blanco con borde negro
bar(t(seg_v), retiros_sf(seg_v), 'FaceColor',[1 1 1], ...
    'EdgeColor',[0 0 0], 'LineWidth',0.8, 'DisplayName','Retiros SF');

% Compras Mesa: negro sólido
bar(t(seg_v), compras_mesa(seg_v), 'FaceColor',[0.15 0.15 0.15], ...
    'EdgeColor','none', 'DisplayName','Compras Mesa');

% Flujo total
plot(t(seg_v), flujo(seg_v), 'k-o', 'LineWidth',2, ...
     'MarkerSize',3, 'MarkerFaceColor','k', 'DisplayName','Total');

yline(0,'k-','LineWidth',0.8,'HandleVisibility','off');
ylim([y_min_k y_max_k]);

legend('Location','best','FontSize',9);
ylabel('USD Millones','FontSize',10);
xlabel('Fecha','FontSize',10);
title(sprintf('Peor Episodio Histórico (Kadane) — %s → %s  (%d días hábiles)\nFlujo neto: %.0f MM  |  Peor día: %.0f MM (%s)', ...
    datestr(t(kad_ini),'dd-mmm-yyyy'), datestr(t(kad_fin),'dd-mmm-yyyy'), kad_dur, ...
    kad_flujo, kad_peor_v, datestr(kad_peor_fecha,'dd-mmm-yyyy')), ...
    'FontWeight','bold','FontSize',11);
grid on; box off; set(gca,'FontSize',9);

% --- Fig 4: Serie completa + episodio Kadane destacado ---
figure('Name','Serie Completa + Kadane','Position',[30 30 1400 500]);
hold on;
bar(t, max(flujo,0), 'FaceColor',[0.78 0.78 0.78], 'EdgeColor','none','DisplayName','Positivo');
bar(t, min(flujo,0), 'FaceColor',[0.3 0.3 0.3],   'EdgeColor','none','DisplayName','Negativo');
y_lim_full = [min(flujo)*1.12, max(flujo)*1.12];
patch([t(kad_ini) t(kad_fin) t(kad_fin) t(kad_ini)], ...
      [y_lim_full(1) y_lim_full(1) y_lim_full(2) y_lim_full(2)], ...
      [1 0.4 0.4], 'FaceAlpha',0.25, 'EdgeColor',[0.8 0 0], 'LineWidth',1.5, ...
      'DisplayName', sprintf('Kadane: %s→%s', datestr(t(kad_ini),'mmm-yy'), datestr(t(kad_fin),'mmm-yy')));
yline(0,'k-','LineWidth',0.8,'HandleVisibility','off');
ylim(y_lim_full);
legend('Location','best','FontSize',9);
ylabel('USD Millones','FontSize',10); xlabel('Fecha','FontSize',10);
title('Flujo Neto Diario — Peor Episodio Histórico destacado (Kadane)','FontWeight','bold','FontSize',11);
grid on; box off; set(gca,'FontSize',9);
sgtitle('AnalisisRetirosME — Serie Completa','FontSize',13,'FontWeight','bold');

% --- Fig 5: Suma acumulada durante el episodio Kadane ---
figure('Name','Kadane - Acumulado','Position',[30 30 900 400]);
seg_kad = kad_ini:kad_fin;
acum_kad = cumsum(flujo(seg_kad));
plot(t(seg_kad), acum_kad, 'k-', 'LineWidth',2);
hold on;
fill([t(seg_kad); flipud(t(seg_kad))], [acum_kad; zeros(numel(seg_kad),1)], ...
     [0.6 0.6 0.6], 'FaceAlpha',0.4, 'EdgeColor','none');
yline(0,'k--','LineWidth',0.8);
[~, ip_min] = min(acum_kad);
plot(t(kad_ini+ip_min-1), acum_kad(ip_min), 'rv', 'MarkerSize',10, ...
     'MarkerFaceColor','r', 'DisplayName', sprintf('Mín: %.0f MM', acum_kad(ip_min)));
legend('Acumulado','Location','best','FontSize',9);
ylabel('Flujo acumulado (MM)','FontSize',10);
xlabel('Fecha','FontSize',10);
title(sprintf('Flujo Acumulado — Episodio Kadane (%s → %s)', ...
    datestr(t(kad_ini),'dd-mmm-yyyy'), datestr(t(kad_fin),'dd-mmm-yyyy')), ...
    'FontWeight','bold','FontSize',11);
grid on; box off; set(gca,'FontSize',9);

fprintf('=============================================================\n');
fprintf('  Análisis completado. Figuras generadas: 5\n');
fprintf('=============================================================\n');

%% ============================================================
%% 5. GUARDAR FIGURAS EN JPG
%% ============================================================
carpeta_out = 'plots_ventana_optima';
if ~exist(carpeta_out, 'dir'); mkdir(carpeta_out); end

figs = findall(0, 'Type', 'figure');
fprintf('\nGuardando %d figuras en carpeta "%s"...\n', numel(figs), carpeta_out);
for f = 1:numel(figs)
    fig    = figs(f);
    nombre = get(fig, 'Name');
    if isempty(nombre); nombre = sprintf('figura_%d', fig.Number); end
    nombre = strrep(nombre, ' ', '_');
    nombre = regexprep(nombre, '[^a-zA-Z0-9_-]', '');
    ruta   = fullfile(carpeta_out, sprintf('%02d_%s.jpg', fig.Number, nombre));
    exportgraphics(fig, ruta, 'Resolution', 200);
    fprintf('  Guardada: %s\n', ruta);
end
fprintf('Listo.\n');
