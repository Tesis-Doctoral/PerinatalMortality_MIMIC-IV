# Tabla de predictores — verificación (modelo prenatal)

Ejecutada el 19/11/2026 con `sql/03_antenatal/04_predictor_table_es.sql` (tarea A2); la versión en inglés no lleva el sufijo `_es`. Versión en inglés: [`predictor_table_antenatal.md`](predictor_table_antenatal.md).

**Etapa del framework:** E6 y E7 (ventana de información y predictores). Crea `mimiciv.antenatal_predictors_v1`, la tabla que leen los modelos, con una fila por admisión y margen (1, 7 y 30 días). Las consultas Q-P1 a Q-P4 verifican la tabla antes de la puerta de tamaño de muestra (P3).

Todas las cifras son conteos agregados de toda la población; ninguna consulta separa eventos y no eventos, salvo el conteo de eventos de Q-P1. No se publica ningún `subject_id`, `hadm_id` ni fila a nivel de paciente.

## Q-P1. Integridad

| Margen | Filas | Admisiones | Pacientes | Eventos estrictos | Con alguna información previa |
|---|---|---|---|---|---|
| 1 día | 19.440 | 19.440 | 13.735 | 129 | 17.285 (88,9%) |
| **7 días** | **19.440** | **19.440** | **13.735** | **129** | **17.166 (88,3%)** |
| 30 días | 19.440 | 19.440 | 13.735 | 129 | 16.919 (87,0%) |

**Qué significa.** Cada margen tiene exactamente una fila por admisión, sin duplicados ni pérdidas, y conserva la población y los eventos de la puerta P1. Las admisiones con alguna información previa coinciden con la auditoría de conteos (Q-A1): por ejemplo, a 7 días, 99 eventos + 11 solo parciales + 17.056 no eventos = 17.166. La tabla y la auditoría están construidas igual.

## Q-P2. Predictores categóricos y binarios (margen de 7 días)

| Predictor | Categoría | Admisiones | % |
|---|---|---|---|
| Raza y etnia | Blanca | 8.715 | 44,8 |
| | Negra | 4.459 | 22,9 |
| | Hispana | 1.876 | 9,7 |
| | Asiática | 1.795 | 9,2 |
| | Otra o desconocida | 2.595 | 13,3 |
| Seguro | Privado | 12.631 | 65,0 |
| | Medicaid | 6.169 | 31,7 |
| | Medicare, otro o faltante | 640 | 3,3 |
| Idioma | Inglés | 17.846 | 91,8 |
| Estado civil | Casada | 11.664 | 60,0 |
| | No casada | 7.391 | 38,0 |
| | Faltante | 385 | 2,0 |
| Alguna hospitalización anterior | Sí | 8.425 | 43,3 |
| Hospitalización en los 90 días previos | Sí | 1.524 | 7,8 |
| Cesárea anterior | Sí | 1.670 | 8,6 |
| Trastorno hipertensivo en embarazo anterior | Sí | 989 | 5,1 |
| Hipertensión crónica | Sí | 472 | 2,4 |
| Diabetes pregestacional | Sí | 267 | 1,4 |
| Diabetes gestacional en embarazo anterior | Sí | 418 | 2,2 |
| Tabaco, alcohol o drogas | Sí | 457 | 2,4 |
| Enfermedad tiroidea | Sí | 728 | 3,7 |
| Resultado adverso en embarazo anterior | Sí | 459 | 2,4 |
| Otra condición crónica de alto riesgo | Sí | 143 | 0,7 |
| Alguna presión de 140/90 o más | Sí | 2.009 | 10,3 |
| Tuvo control prenatal en este hospital | Sí | 14.954 | 76,9 |
| Antecedente hipertensivo (cualquiera) | Sí | 1.348 | 6,9 |
| Diabetes (cualquiera) | Sí | 669 | 3,4 |

**Qué significa.**
1. Las hospitalizaciones anteriores (8.425) y los antecedentes coinciden con la auditoría (Q-A4).
2. Ninguna categoría queda vacía. La más rara es "otra condición crónica de alto riesgo" (143 admisiones, 0,7%); por eso se definió como compuesto.
3. Tres de cada cuatro mujeres tuvieron control prenatal en el hospital, y una de cada diez tuvo alguna presión elevada en el embarazo actual.

## Q-P3. Predictores continuos (margen de 7 días)

| Predictor | Con valor | % | P5 | P25 | Mediana | P75 | P95 |
|---|---|---|---|---|---|---|---|
| Edad (años) | 19.440 | 100,0 | 22 | 29 | 33 | 36 | 41 |
| Última sistólica (mmHg) | 11.916 | 61,3 | 98 | 108 | 116 | 122 | 136 |
| Última diastólica (mmHg) | 11.916 | 61,3 | 58 | 64 | 70 | 78 | 86 |
| Último IMC (kg/m²) | 8.304 | 42,7 | 22,7 | 27,0 | 30,5 | 35,1 | 44,2 |
| Última hemoglobina (g/dL) | 11.435 | 58,8 | 9,6 | 10,8 | 11,5 | 12,2 | 13,3 |

**Qué significa.**
1. Las distribuciones son clínicamente plausibles para mujeres embarazadas: presión normal en la mayoría, IMC de embarazo (incluye la ganancia de peso) y hemoglobina con la caída fisiológica del embarazo.
2. La cobertura es menor que en la auditoría (Q-A5: presión en el 68%; Q-A6: hemoglobina en el 69%) porque aquí solo cuentan los valores del embarazo actual (entre 280 y 7 días antes del ingreso). Es lo esperado.
3. **Faltantes:** sin presión el 38,7%, sin hemoglobina el 41,2% y sin IMC el 57,3%. La mayoría corresponde a mujeres sin control prenatal en el hospital (23,1%), pero el IMC falta también en muchas que sí lo tuvieron. El tratamiento de los faltantes debe fijarse antes de la puerta P3 (ver la sección final).

## Q-P4. Origen del IMC (margen de 7 días)

| Registrado | Calculado con peso y talla | Faltante |
|---|---|---|
| 8.282 | 22 | 11.136 |

**Qué significa.** El cálculo con peso y talla casi no agrega valores (22). El sistema registra el IMC siempre que hay peso y talla, así que las mujeres sin IMC tampoco tienen talla. El IMC queda como el predictor continuo con más faltantes.

## Lo que queda para el modelo

- La tabla pasa la verificación: población, eventos y unicidad correctos en los tres márgenes, y conteos iguales a la auditoría.
- **Tratamiento de los faltantes (decidido el 19/11/2026: opción 1, imputación múltiple; registrado en la ficha del desenlace)** de presión, IMC y hemoglobina. Las opciones son:
  1. imputación múltiple dentro de cada partición de la validación, con el indicador "tuvo control prenatal en este hospital" como único indicador (sin parámetros extra; 27 parámetros);
  2. imputación simple más un indicador de faltante por medición (presión, IMC, hemoglobina; 30 parámetros).
- Siguiente paso: puerta de tamaño de muestra (P3) con el R² de Cox-Snell observado.

*Confidencial: uso interno del proyecto de investigación.*
