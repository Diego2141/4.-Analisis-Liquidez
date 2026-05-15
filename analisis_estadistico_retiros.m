%% ANÁLISIS ESTADÍSTICO - AnalisisRetirosME
% Carga y análisis completo de las series temporales contenidas en el archivo

clc; clear; close all;

%% 1. CARGA DE DATOS
load('AnalisisRetirosME.mat');

% Extraer columnas y asignar nombres descriptivos
saldo    = data_values(:, 1);   % Saldo / Balance
retiros  = data_values(:, 2);   % Retiros / Flujo principal
flujo_c3 = data_values(:, 3);   % Flujo complementario 1
flujo_c4 = data_values(:, 4);   % Flujo complementario 2

series       = {saldo, retiros, flujo_c3, flujo_c4};
nombres      = {'Saldo RIN', 'Retiros SF', 'Compras netas mesa', 'Compras netas f/mesa'};
n_series     = numel(series);
n_obs        = size(data_values, 1);

% Fechas
tiene_fechas = exist('dates','var') && isa(dates,'datetime');
if tiene_fechas
    t = dates(:);
    fprintf('Rango de fechas: %s  →  %s\n', datestr(t(1)), datestr(t(end)));
else
    t = (1:n_obs)';
end

fprintf('=============================================================\n');
fprintf('  ANÁLISIS ESTADÍSTICO - AnalisisRetirosME\n');
fprintf('  Observaciones: %d  |  Series: %d\n', n_obs, n_series);
if tiene_fechas
    fprintf('  Período: %s  →  %s\n', datestr(t(1),'dd-mmm-yyyy'), datestr(t(end),'dd-mmm-yyyy'));
end
fprintf('=============================================================\n\n');

%% 2. ESTADÍSTICAS DESCRIPTIVAS
fprintf('--- ESTADÍSTICAS DESCRIPTIVAS ---\n');
fprintf('%-12s %10s %10s %10s %10s %10s %10s %10s\n', ...
    'Serie','Media','Mediana','Std','Min','Max','Asimetría','Curtosis');
fprintf('%s\n', repmat('-',1,82));

stats_tabla = zeros(n_series, 8);
for i = 1:n_series
    x = series{i};
    mu     = mean(x);
    med    = median(x);
    sigma  = std(x);
    mn     = min(x);
    mx     = max(x);
    sk     = skewness(x);
    kt     = kurtosis(x);
    cv     = sigma / abs(mu) * 100;
    stats_tabla(i,:) = [mu, med, sigma, mn, mx, sk, kt, cv];
    fprintf('%-12s %10.2f %10.2f %10.2f %10.2f %10.2f %10.4f %10.4f\n', ...
        nombres{i}, mu, med, sigma, mn, mx, sk, kt);
end
fprintf('\nCoeficiente de variación (%%):\n');
for i = 1:n_series
    fprintf('  %-12s  CV = %.2f%%\n', nombres{i}, stats_tabla(i,8));
end

%% 3. PERCENTILES Y CUANTILES
fprintf('\n--- PERCENTILES ---\n');
pcts = [1, 5, 10, 25, 50, 75, 90, 95, 99];
fprintf('%-12s', 'Serie');
for p = pcts; fprintf('%8s', ['p' num2str(p)]); end
fprintf('\n%s\n', repmat('-',1,12+8*numel(pcts)));
for i = 1:n_series
    fprintf('%-12s', nombres{i});
    vals = prctile(series{i}, pcts);
    for v = vals; fprintf('%8.2f', v); end
    fprintf('\n');
end

%% 4. PRUEBAS DE NORMALIDAD
fprintf('\n--- PRUEBAS DE NORMALIDAD ---\n');
fprintf('%-12s  %10s %8s    %10s %8s    %10s %8s\n', ...
    'Serie','JB stat','JB p-val','KS stat','KS p-val','SW stat','SW p-val');
fprintf('%s\n', repmat('-',1,75));
for i = 1:n_series
    x = series{i};
    % Jarque-Bera
    [~, p_jb, jbstat] = jbtest(x, 0.05);
    % Kolmogorov-Smirnov
    [~, p_ks, ks_stat] = kstest(zscore(x));
    % Lilliefors (proxy para Shapiro si N>50)
    try
        [~, p_lf, lf_stat] = lillietest(x);
    catch
        p_lf = NaN; lf_stat = NaN;
    end
    fprintf('%-12s  %10.4f %8.4f    %10.4f %8.4f    %10.4f %8.4f\n', ...
        nombres{i}, jbstat, p_jb, ks_stat, p_ks, lf_stat, p_lf);
end
fprintf('  H0: distribución normal  |  p < 0.05 → rechazar normalidad\n');

%% 5. PRUEBAS DE ESTACIONARIEDAD (ADF via autocorrelación y varianza)
fprintf('\n--- ANÁLISIS DE ESTACIONARIEDAD (varianza rodante) ---\n');
ventana = 250;  % ~1 año de días hábiles
fprintf('Ventana rodante: %d observaciones\n', ventana);
for i = 1:n_series
    x = series{i};
    n_v = floor(n_obs / ventana);
    medias_v = zeros(n_v,1);
    vars_v   = zeros(n_v,1);
    for j = 1:n_v
        bloque = x((j-1)*ventana+1 : j*ventana);
        medias_v(j) = mean(bloque);
        vars_v(j)   = var(bloque);
    end
    cv_media = std(medias_v)/abs(mean(medias_v))*100;
    cv_var   = std(vars_v)/mean(vars_v)*100;
    fprintf('  %-12s  CV(media)=%6.2f%%  CV(varianza)=%6.2f%%  → %s\n', ...
        nombres{i}, cv_media, cv_var, ...
        ternary(cv_media<15 && cv_var<50, 'Posiblemente estacionaria', 'Posiblemente NO estacionaria'));
end

%% 6. AUTOCORRELACIÓN
fprintf('\n--- AUTOCORRELACIÓN (lag 1, 5, 10, 21) ---\n');
lags_check = [1, 5, 10, 21];
fprintf('%-12s', 'Serie');
for lg = lags_check; fprintf('%10s', ['AC(', num2str(lg), ')']); end
fprintf('\n%s\n', repmat('-',1,12+10*numel(lags_check)));
for i = 1:n_series
    x = series{i};
    fprintf('%-12s', nombres{i});
    acf_vals = autocorr(x, 'NumLags', max(lags_check));
    for lg = lags_check
        fprintf('%10.4f', acf_vals(lg+1));
    end
    fprintf('\n');
end

%% 7. DETECCIÓN DE OUTLIERS (método IQR y z-score)
fprintf('\n--- DETECCIÓN DE OUTLIERS ---\n');
fprintf('%-12s  %8s  %8s  %10s  %10s\n', 'Serie','IQR out','Z>3 out','% IQR','% Z>3');
fprintf('%s\n', repmat('-',1,55));
outlier_info = cell(n_series, 1);
for i = 1:n_series
    x = series{i};
    q1 = prctile(x,25); q3 = prctile(x,75);
    iqr_v = q3 - q1;
    lim_inf = q1 - 1.5*iqr_v;
    lim_sup = q3 + 1.5*iqr_v;
    out_iqr = sum(x < lim_inf | x > lim_sup);
    out_z   = sum(abs(zscore(x)) > 3);
    outlier_info{i} = struct('iqr', out_iqr, 'z', out_z, ...
        'lim_inf', lim_inf, 'lim_sup', lim_sup);
    fprintf('%-12s  %8d  %8d  %9.2f%%  %9.2f%%\n', ...
        nombres{i}, out_iqr, out_z, out_iqr/n_obs*100, out_z/n_obs*100);
end

%% 8. CORRELACIÓN ENTRE SERIES
fprintf('\n--- MATRIZ DE CORRELACIÓN ---\n');
C = corr(data_values);
fprintf('%-12s', '');
for i = 1:n_series; fprintf('%12s', nombres{i}); end
fprintf('\n%s\n', repmat('-',1,12+12*n_series));
for i = 1:n_series
    fprintf('%-12s', nombres{i});
    for j = 1:n_series
        fprintf('%12.4f', C(i,j));
    end
    fprintf('\n');
end

%% 9. GRÁFICAS
fig_h = 1;

% 9a. Series temporales
figure(fig_h); fig_h = fig_h+1;
tiledlayout(n_series, 1, 'TileSpacing','compact');
for i = 1:n_series
    nexttile;
    plot(t, series{i}, 'LineWidth', 0.8);
    title(nombres{i}, 'FontWeight','bold');
    if tiene_fechas; xlabel('Fecha'); else; xlabel('Observación'); end
    ylabel('Valor');
    grid on; box off;
end
sgtitle('Series Temporales - AnalisisRetirosME', 'FontSize',13,'FontWeight','bold');

% 9b. Histogramas con curva normal
figure(fig_h); fig_h = fig_h+1;
tiledlayout(2, 2, 'TileSpacing','compact');
for i = 1:n_series
    nexttile;
    x = series{i};
    histogram(x, 50, 'Normalization','pdf', 'FaceColor',[0.2 0.5 0.8], 'EdgeAlpha',0.3);
    hold on;
    xi = linspace(min(x), max(x), 200);
    plot(xi, normpdf(xi, mean(x), std(x)), 'r-', 'LineWidth', 2);
    title(nombres{i}); xlabel('Valor'); ylabel('Densidad');
    legend('Empírica','Normal teórica','Location','best');
    grid on; box off;
end
sgtitle('Distribuciones - AnalisisRetirosME', 'FontSize',13,'FontWeight','bold');

% 9c. Boxplots
figure(fig_h); fig_h = fig_h+1;
boxplot(data_values, 'Labels', nombres, 'Whisker', 1.5);
title('Boxplots por Serie', 'FontSize',13,'FontWeight','bold');
ylabel('Valor'); grid on; box off;

% 9d. Autocorrelogramas (ACF)
figure(fig_h); fig_h = fig_h+1;
tiledlayout(2, 2, 'TileSpacing','compact');
for i = 1:n_series
    nexttile;
    autocorr(series{i}, 'NumLags', 40);
    title(['ACF - ' nombres{i}]);
end
sgtitle('Función de Autocorrelación (ACF)', 'FontSize',13,'FontWeight','bold');

% 9e. Autocorrelogramas parciales (PACF)
figure(fig_h); fig_h = fig_h+1;
tiledlayout(2, 2, 'TileSpacing','compact');
for i = 1:n_series
    nexttile;
    parcorr(series{i}, 'NumLags', 40);
    title(['PACF - ' nombres{i}]);
end
sgtitle('Función de Autocorrelación Parcial (PACF)', 'FontSize',13,'FontWeight','bold');

% 9f. QQ-plots
figure(fig_h); fig_h = fig_h+1;
tiledlayout(2, 2, 'TileSpacing','compact');
for i = 1:n_series
    nexttile;
    qqplot(series{i});
    title(['QQ-Plot - ' nombres{i}]);
    grid on;
end
sgtitle('QQ-Plots vs Normal', 'FontSize',13,'FontWeight','bold');

% 9g. Varianza y media rodante (serie Retiros)
figure(fig_h); fig_h = fig_h+1;
x = retiros;
media_rod = movmean(x, ventana);
std_rod   = movstd(x, ventana);
subplot(2,1,1);
plot(t, x, 'Color',[0.7 0.7 0.7]); hold on;
plot(t, media_rod, 'b-', 'LineWidth', 1.5);
title('Retiros: Media rodante'); ylabel('Valor'); legend('Serie','Media 250 obs'); grid on;
if tiene_fechas; xlabel('Fecha'); end
subplot(2,1,2);
plot(t, std_rod, 'r-', 'LineWidth', 1.2);
title('Retiros: Desviación estándar rodante (ventana 250)');
ylabel('Std'); if tiene_fechas; xlabel('Fecha'); else; xlabel('Observación'); end
grid on;
sgtitle('Análisis de Estacionariedad - Retiros', 'FontSize',13,'FontWeight','bold');

% 9h. Matriz de correlación (heatmap)
figure(fig_h); fig_h = fig_h+1;
imagesc(C);
colorbar; colormap(redblue_map());
clim([-1 1]);
set(gca, 'XTick',1:n_series, 'XTickLabel',nombres, ...
         'YTick',1:n_series, 'YTickLabel',nombres);
title('Matriz de Correlación', 'FontSize',13,'FontWeight','bold');
for i = 1:n_series
    for j = 1:n_series
        text(j, i, sprintf('%.2f', C(i,j)), 'HorizontalAlignment','center', ...
            'FontWeight','bold', 'Color', ternary(abs(C(i,j))>0.5,'w','k'));
    end
end

fprintf('\n=============================================================\n');
fprintf('  Análisis completado. Figuras generadas: %d\n', fig_h-1);
fprintf('=============================================================\n');

%% GUARDAR FIGURAS EN JPG
carpeta_out = 'plots_estadistico';
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

%% FUNCIONES AUXILIARES
function out = ternary(cond, a, b)
    if cond; out = a; else; out = b; end
end

function cmap = redblue_map()
    r = [linspace(0.7,1,64)', linspace(0.7,1,64)', linspace(1,0.7,64)'; ...
         linspace(1,0.6,64)', linspace(0.7,0,64)', linspace(0.7,0,64)'];
    cmap = r;
    % Mapa simple azul-blanco-rojo
    n = 128;
    cmap = zeros(n,3);
    half = n/2;
    cmap(1:half,1)   = linspace(0,1,half);
    cmap(1:half,2)   = linspace(0,1,half);
    cmap(1:half,3)   = 1;
    cmap(half+1:n,1) = 1;
    cmap(half+1:n,2) = linspace(1,0,half);
    cmap(half+1:n,3) = linspace(1,0,half);
end
