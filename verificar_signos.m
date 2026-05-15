%% VERIFICACIÓN DE SIGNOS — Retiros SF y Compras Netas Mesa
clc; clear; close all;

load('AnalisisRetirosME.mat');

retiros_sf   = data_values(:, 2);
compras_mesa = data_values(:, 3);

tiene_fechas = exist('dates','var') && isa(dates,'datetime');
if tiene_fechas
    t = dates(:);
else
    t = (datetime('2000-01-01') + caldays(0:size(data_values,1)-1))';
end

fprintf('--- RETIROS SF ---\n');
fprintf('  Positivos: %d días  (%.1f%%)\n', sum(retiros_sf>0), sum(retiros_sf>0)/numel(retiros_sf)*100);
fprintf('  Negativos: %d días  (%.1f%%)\n', sum(retiros_sf<0), sum(retiros_sf<0)/numel(retiros_sf)*100);
fprintf('  Media     : %.2f MM\n', mean(retiros_sf));
fprintf('  Max       : %.2f MM  (%s)\n', max(retiros_sf), datestr(t(retiros_sf==max(retiros_sf)),'dd-mmm-yyyy'));
fprintf('  Min       : %.2f MM  (%s)\n', min(retiros_sf), datestr(t(retiros_sf==min(retiros_sf)),'dd-mmm-yyyy'));

fprintf('\n--- COMPRAS NETAS MESA ---\n');
fprintf('  Positivos: %d días  (%.1f%%)\n', sum(compras_mesa>0), sum(compras_mesa>0)/numel(compras_mesa)*100);
fprintf('  Negativos: %d días  (%.1f%%)\n', sum(compras_mesa<0), sum(compras_mesa<0)/numel(compras_mesa)*100);
fprintf('  Media     : %.2f MM\n', mean(compras_mesa));

% --- Gráfica completa con fechas ---
figure('Position',[30 30 1400 500]);
hold on;
bar(t, max(retiros_sf,0), 'FaceColor',[0.2 0.6 0.9], 'EdgeColor','none','DisplayName','Positivo');
bar(t, min(retiros_sf,0), 'FaceColor',[0.9 0.2 0.2], 'EdgeColor','none','DisplayName','Negativo');
yline(0,'k-','LineWidth',1);
ylabel('MM'); xlabel('Fecha');
title('Retiros SF — Serie completa con fechas','FontWeight','bold');
legend('Location','best'); grid on; box off;

% --- Zoom primeros 2 años para ver detalle ---
mask = t >= t(1) & t <= t(1) + calyears(2);
figure('Position',[30 30 1400 450]);
hold on;
bar(t(mask), max(retiros_sf(mask),0), 'FaceColor',[0.2 0.6 0.9],'EdgeColor','none','DisplayName','Positivo');
bar(t(mask), min(retiros_sf(mask),0), 'FaceColor',[0.9 0.2 0.2],'EdgeColor','none','DisplayName','Negativo');
yline(0,'k-','LineWidth',1);
ylabel('MM'); xlabel('Fecha');
title(sprintf('Retiros SF — Zoom primeros 2 años (%s → %s)', ...
    datestr(t(1),'mmm-yyyy'), datestr(t(find(mask,1,'last')),'mmm-yyyy')),'FontWeight','bold');
legend('Location','best'); grid on; box off;
