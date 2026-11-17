# Framework para modelos de desenlaces en MIMIC-IV — maqueta

Maqueta en borrador, versión 0.1, escrita el 29/10/2026. Nada de esto está implementado todavía como código compartido. Se construye a partir de dos casos reales, el proyecto materno (`MaternalMortality_MIMIC-IV`: morbilidad materna grave y muerte materna) y este proyecto (muerte perinatal antes del nacimiento), y deja una ranura para el modelo neonatal. El estado del caso materno sale de su README, de su plan de análisis de los cuadernos y de su auditoría de conteos; el estado de este proyecto sale de [`analysis_plan_es.md`](analysis_plan_es.md) y [`count_audit_es.md`](count_audit_es.md). El caso neonatal no se ha mapeado. Versión en inglés: [`framework.md`](framework.md). Una vista interactiva del mapa de etapas es el artefacto "Framework de desenlaces MIMIC-IV".

## 1. Por qué un framework

El proyecto materno recorrió el mismo camino que este proyecto está siguiendo: un primer modelo exploratorio (mortalidad materna), una auditoría de conteos que mostró cuán pocos eran los eventos, una revisión de las etiquetas, un giro hacia la morbilidad materna grave como desenlace principal con la muerte materna como pregunta de viabilidad, análisis de sensibilidad y reporte. Escribir ese camino una sola vez, como etapas con entradas y salidas fijas, convierte un nuevo desenlace en un módulo y no en un proyecto nuevo, y muestra qué pasos se saltó un modelo.

## 2. Principios que no cambian

1. **Auditar antes de modelar.** Los conteos que deciden el diseño (población, unidad, definición, tiempo, tamaño de muestra) se miden y se registran antes de ajustar cualquier modelo.
2. **Sin solapamiento y sin selección por desenlace.** Una regla de la cohorte se mide primero como columna y solo después se aplica como filtro, con su análisis de sensibilidad.
3. **La etiqueta es un sustituto documentado.** Un catálogo verificado de códigos (título oficial, nivel, fuente, fecha) y una tabla de etiqueta con una fila por unidad, donde las definiciones de sensibilidad son columnas y no filtros.
4. **Validación agrupada por paciente, todo dentro de la parte de entrenamiento.** Imputación, escalado, ajuste de hiperparámetros, apilado y recalibración se ajustan dentro de cada pliegue de entrenamiento.
5. **El punto de predicción y la ventana de información se fijan antes que los predictores.** Los diagnósticos de la misma admisión no son predictores en el modelo principal.
6. **Cada elección es una decisión numerada** (D1, D2, …) con su evidencia, y con un análisis de sensibilidad cuando la elección podría cambiar el resultado.
7. **Solo salidas agregadas.** Ningún `subject_id`, `hadm_id` ni `stay_id` en un resultado publicado.
8. **Reproducibilidad.** Configuración fija, conteos esperados certificados que detienen una corrida cuando la población no es la auditada, scripts SQL en pares EN/ES comprobados por script, reporte TRIPOD+AI.

## 3. Arquitectura

Tres capas y las puertas entre etapas. La capa de **método** es todo lo que no depende del dataset ni del desenlace: las etapas, la validación, el ensamble apilado, las métricas y el reporte. El **adaptador de datos** es el código que convierte un dataset en la tabla que lee el método (SQL para MIMIC-IV hoy; el dataset neonatal y los datos de una entidad de salud necesitarán el suyo). El **módulo de desenlace** es el pequeño conjunto de elecciones que definen un desenlace (sección 5). Las **puertas** son las decisiones que deben quedar registradas antes de que empiece la siguiente etapa. El método nunca lee un dataset directamente: lee la tabla del contrato de la sección 3.1.

![Camino de un modelo defendible: etapas E0 a E11, tres puertas de decisión, ensamble apilado dentro de E8, rama de viabilidad y la etapa preventiva E10](framework_flow_es.svg)

*Figura. El camino de todo desenlace. Los puntos marcan las etapas donde entra la ficha del desenlace; los cuadrados marcan las etapas que dependen del adaptador de datos; la ruta ámbar discontinua es la rama de viabilidad; el bloque verdeazulado discontinuo es la etapa preventiva propuesta.*

El recorrido por las etapas es el mismo para todo desenlace. Lo que cambia es la ficha del desenlace que alimenta E1, E2, E5, E6, E9 y E10. La puerta de E7 es donde el proyecto materno decidió que la muerte materna (3 eventos entre los partos elegibles) solo podía ser un análisis de viabilidad, mientras que la morbilidad materna grave (445 eventos) sí se podía modelar.

## 3.1 Contrato de datos

Sea cual sea el dataset, un adaptador debe entregar una tabla con una fila por unidad de análisis y estas columnas. Las etapas E4 a E11 corren solo desde esa tabla.

| Columna | Significado | Adaptador de MIMIC-IV hoy |
|---|---|---|
| `unit_id` | Identificador de una unidad de análisis | `hadm_id` |
| `group_id` | Lo que nunca debe quedar repartido entre entrenamiento y prueba | `subject_id` (paciente) |
| `t0` | Tiempo cero | Hora de ingreso |
| `t_pred` | Punto de predicción | `t0` + 6 h (perinatal), `t0` + 24 h (materno) |
| `label_*` | Etiqueta principal y etiquetas de sensibilidad, como columnas | `fetal_death_label_v2`, `label_admission_v2` |
| `x_*` con su momento de disponibilidad | Predictores y el momento en que se conoció cada valor | Tabla de predictores con la regla de ventana de 24 horas |
| `period` | Período calendario o era de codificación, si el dataset la tiene | Versión de CIE, grupo de año ancla |

Reglas para cualquier adaptador: una fila por unidad; ningún identificador personal sale de la base; los conteos reproducen los conteos esperados de la configuración; la misma tabla alimenta la auditoría y los modelos. Si un dataset no tiene identificador de grupo o marcas de tiempo, el adaptador debe decirlo y el framework registra la decisión (para el dataset neonatal: la madre o el recién nacido como grupo, y si aplica E4).

## 3.2 Qué capa es dueña de cada etapa

| Etapa | Capa |
|---|---|
| E0 Gobernanza | Método |
| E1 Universo y población | Adaptador de datos |
| E2 Definición del desenlace | Módulo de desenlace, leyendo las tablas de códigos del adaptador |
| E3 Auditoría de conteos | Estructura del método (grupos A–F), consultas del adaptador |
| E4 Unidad de análisis y solapamiento | Adaptador de datos |
| E5 Punto de predicción y ventana | Módulo de desenlace, con las marcas de tiempo del adaptador |
| E6 Predictores | Adaptador de datos y módulo de desenlace |
| E7 Puerta de viabilidad | Método |
| E8 Modelado, validación y métricas | Método |
| E9 Sensibilidad y robustez | Método, más el set propio del desenlace |
| E10 De la predicción a la estrategia de prevención | Método, módulo de desenlace y la entidad de salud |
| E11 Reporte | Método |
## 4. Mapa de etapas

Las etapas se numeran E0 a E11 (E de etapa) para que no choquen con los análisis de sensibilidad S1–S11 del plan de análisis.

| Etapa | Pregunta que responde | Parte que se reutiliza (método o adaptador de MIMIC-IV) | Parámetro del desenlace |
|---|---|---|---|
| E0 Gobernanza y configuración | ¿Qué se fija antes de correr nada para que los análisis sean comparables? | Registro de decisiones, libro de seguimiento, semilla y ajustes fijos (5 × 3 pliegues, bootstrap, árboles), conteos esperados, pares de scripts EN/ES | Archivo de configuración del desenlace (propuesta FD2) |
| E1 Universo y población | ¿Qué admisiones se pueden estudiar? | Tablas del universo obstétrico (`cohort_obstetric_v2`, `hadm_delivery_v2`, `obstetric_dx_v2`) | Regla de población |
| E2 Definición del desenlace | ¿Qué cuenta exactamente como evento y de qué fuentes? | Estructura del catálogo de códigos (nivel, título, fuente, fecha); tabla de etiqueta, una fila por unidad, sensibilidades como columnas | La lista de códigos y los niveles |
| E3 Auditoría de conteos | ¿Cuántos eventos, dónde, cuándo y con qué solapamiento? | Grupos A–F: base, eventos, solapamiento de pacientes, era, elegibilidad y tiempo, predictores | Eventos por definición |
| E4 Unidad de análisis y solapamiento | ¿Qué es un registro y quién aparece en ambos lados de una partición? | Columnas de unidad (rango de admisión, intervalo, cadena de embarazo, primera admisión) sin columnas de desenlace; simulación de partición por admisión | Ninguno |
| E5 Punto de predicción y ventana | ¿Cuándo se predice y qué puede usar la predicción? | Tiempo cero, punto de predicción, ventana de información, elegibilidad, eventos perdidos, sin diagnósticos de la misma admisión | El punto de predicción |
| E6 Predictores | ¿Qué variables, con qué cobertura y límites? | Diccionario, regla de cobertura del 10 %, límites de plausibilidad, indicadores de faltantes | Bloques propios del desenlace |
| E7 Puerta de viabilidad | ¿Hay eventos suficientes para modelar? | Criterios de Riley, eventos por parámetro, decisión: modelo completo o solo viabilidad | Ninguno |
| E8 Modelado, validación y métricas | ¿Qué tan bien funciona y con qué incertidumbre? | Validación anidada agrupada por paciente y pipeline sin fuga; modelos base (regresión logística, bosque aleatorio, árboles extra, XGBoost); **ensamble apilado con meta-aprendiz logístico como estrategia por defecto**, siempre comparado con la regresión logística y con el mejor modelo base bajo la misma validación; recalibración, bootstrap por paciente, calibración, curva de decisión, diferencias pareadas | Ninguno |
| E9 Sensibilidad y robustez | ¿El resultado resiste otras elecciones razonables? | Remuestreo, era y versión de CIE, validación temporal, indicadores de disponibilidad, momento de los eventos frente al punto de predicción | El set de sensibilidad propio del desenlace |
| E10 De la predicción a la estrategia de prevención | ¿Cómo se convierte la estimación de riesgo en una decisión y una acción en una entidad de salud? | Niveles de riesgo y umbrales tomados de la curva de decisión y de los eventos capturados en el 5 % y 10 % de mayor riesgo, ligados a la capacidad de la entidad; predictores accionables frente a no accionables; revisión por subgrupos y equidad; diseño de la alerta con validación humana; validación y recalibración local antes de usarlo; monitoreo de la calibración | Las acciones que la entidad puede tomar para ese desenlace, definidas con su equipo clínico |
| E11 Reporte | ¿Qué se entrega? | TRIPOD+AI, suplementos de listas de códigos, tablas de faltantes, archivos de salida agregados | Texto del desenlace |

## 4.1 El apilado dentro de E8

El apilado es la estrategia de modelado del framework y es lo que tienen en común los estudios materno y neonatal (el manuscrito neonatal es un ensamble apilado; el modelo de morbilidad materna grave usa un ensamble apilado con meta-aprendiz logístico). Lo que el framework fija es cómo se construye y cómo se juzga:

*Dibujado dentro de la etapa E8 de la figura de la sección 3: cuatro modelos base, predicciones fuera de muestra, meta-aprendiz logístico, recalibración de Platt y la comparación pareada.*

1. Los modelos base y el meta-aprendiz se ajustan en pliegues anidados; el meta-aprendiz solo ve predicciones fuera de muestra.
2. La recalibración se ajusta dentro de la parte de entrenamiento y se reporta como parte del procedimiento completo.
3. El apilado nunca se reporta solo: el framework exige la diferencia pareada frente a la regresión logística regularizada y frente al mejor modelo base, con intervalos de bootstrap por paciente. En el estudio materno la ganancia del apilado sobre la regresión logística fue pequeña (AUROC +0.009, intervalo del 95 % de 0.002 a 0.016) y no hubo diferencia con XGBoost, así que la comparación es parte del resultado y no un trámite.
4. Sea cual sea el desenlace, se usan los mismos cuatro modelos base y el mismo meta-aprendiz, de modo que los desenlaces se puedan comparar entre sí.

## 4.2 E10 en detalle: de la predicción a la estrategia de prevención

El título de la tesis pide modelos que apoyen estrategias de prevención y planes de acción en entidades de salud, así que el framework necesita una etapa después de validar el modelo. Esta etapa es una propuesta: ninguno de los tres desenlaces ha pasado por ella, y el manuscrito materno declara que sus modelos son prototipos de investigación que no deben guiar decisiones clínicas individuales. Su entregable es una hoja de estrategia de una página por desenlace:

1. Niveles de riesgo y el umbral de cada nivel, con su razón (por ejemplo la proporción de eventos capturados en el 5 % y 10 % de mayor riesgo y el rango de la curva de decisión), y la capacidad de la entidad para actuar en cada nivel.
2. Qué predictores se pueden intervenir o vigilar y cuáles solo describen a la paciente.
3. Desempeño y calibración por subgrupo (franja de edad, tipo de seguro, era de CIE), reportados aunque sean malos.
4. Quién recibe la alerta, quién la valida (un clínico responsable) y qué acción sigue.
5. Validación y recalibración local con datos de la propia entidad antes de cualquier uso, porque los modelos se construyen en un solo hospital de EE. UU.
6. Una métrica de monitoreo y una fecha de revisión (deriva de la calibración, tasa de eventos).

## 5. Módulo de desenlace

Un módulo es una ficha con los campos de abajo. Llenarla es lo único que debe hacer un desenlace nuevo antes de que corran las etapas. La columna perinatal se llena con este proyecto; las columnas maternas, con el proyecto materno; la columna neonatal lista lo que falta por definir.

| Campo | Morbilidad materna grave | Muerte materna | Muerte perinatal antes del nacimiento | Neonatal (ranura) |
|---|---|---|---|---|
| Dataset | MIMIC-IV | MIMIC-IV | MIMIC-IV | No es MIMIC-IV; aún no disponible |
| Estado | Manuscrito en revisión | Solo viabilidad | En curso: auditoría y etiqueta listas | Existe manuscrito; sin mapear |
| Unidad | Hospitalización de parto | Hospitalización de parto | Hospitalización de parto (D4) | Por definir (estancia neonatal) |
| Población | Hospitalizaciones de parto aún hospitalizadas a las 24 h: 19,383 | La misma | Marca de parto o código de mortinato (D3): 19,440 | Por definir |
| Definición del evento | Al menos uno de los 20 indicadores activos del CDC (CIE-9-CM, CIE-10-CM/PCS) | Muerte en la misma admisión | Código estricto de muerte fetal a cualquier edad gestacional; niveles estricto, parcial, excluido | Por definir |
| Eventos | 445 (2.30 %) | 3 | 142 con códigos parciales, 129 estrictos | Por definir |
| Momento del evento | Códigos de diagnóstico sin hora; códigos de procedimiento con fecha | Hora de la muerte | Ninguno: código de egreso | Por confirmar |
| Punto de predicción | 24 h después del ingreso | 24 h | Ingreso + 6 h (D6) | Por definir |
| Tabla de etiqueta | `label_admission_v2` (modelo B) | La misma tabla (modelo A) | `fetal_death_label_v2` | Por definir |
| Puerta de tamaño de muestra | Superada: modelo completo | No superada: viabilidad | Pendiente (D12) | Por definir |
| Set de sensibilidad propio | Indicador de creatinina, solo renal, momento frente al punto de predicción | Ninguno | Estricta más parcial, 22 y 28 semanas, exclusión de códigos de pérdida temprana (S1–S11 del plan) | Por definir |
| Uso en la entidad (E10) | Aún no: el manuscrito llama a los modelos prototipos de investigación, no para decisiones individuales | No aplica | Por definir | Por definir |
| Riesgo conocido | La creatinina faltante codifica quién se midió | Muy pocos eventos | La etiqueta no tiene hora; pérdidas previables; semanas solo en CIE-10 | Por definir |

## 6. Escalera de desenlaces

Un patrón que siguió el proyecto materno y que este proyecto está siguiendo: primero se audita un desenlace objetivo; si la auditoría muestra muy pocos eventos en el punto de predicción, un desenlace relacionado con más eventos pasa a ser el modelo principal y el objetivo se conserva como análisis de viabilidad.

*Dibujado como la rama de viabilidad de la figura de la sección 3: la puerta 3 envía un desenlace con muy pocos eventos a un análisis de viabilidad y uno con eventos suficientes al modelo completo.*

En el proyecto materno el objetivo era la muerte materna y el desenlace relacionado fue la morbilidad materna grave. Para la muerte perinatal antes del nacimiento la auditoría encontró 129 eventos estrictos en 19,440 admisiones; la decisión D12 dirá si bastan para el modelo completo.

## 7. Madurez por etapa

Estado al 29/10/2026. "Compartido" significa que la etapa es la misma que para la morbilidad materna grave.

| Etapa | Morbilidad materna grave | Muerte materna | Muerte perinatal antes del nacimiento | Neonatal |
|---|---|---|---|---|
| E0 Gobernanza | Hecho | Compartido | En curso (D9–D14 abiertas) | Por mapear |
| E1 Universo y población | Hecho | Compartido | Hecho (D1, D3) | Por mapear |
| E2 Definición del desenlace | Hecho (lista oficial del CDC) | Hecho | Hecho (T15, T16) | Por mapear |
| E3 Auditoría de conteos | Hecho | Hecho | Grupos A–E hechos, grupo F pendiente | Por mapear |
| E4 Unidad y solapamiento | Hecho (cuaderno 01) | Compartido | Pendiente (T17, T13) | Por mapear |
| E5 Punto de predicción y ventana | Hecho (24 h) | Compartido | Decidido (D6–D8), tabla pendiente | Por mapear |
| E6 Predictores | Hecho | Compartido | Pendiente (grupo F) | Por mapear |
| E7 Puerta de viabilidad | Hecho: modelo completo | Hecho: solo viabilidad | Pendiente (D12) | Por mapear |
| E8 Modelado y validación | Hecho (cuaderno 02) | No se modela | Pendiente | Por mapear |
| E9 Sensibilidad | Hecho (cuadernos 03–07) | No aplica | Definida (S1–S11), sin correr | Por mapear |
| E10 Predicción a estrategia | Pendiente | No aplica | Pendiente | Por mapear |
| E11 Reporte | En revisión (TRIPOD+AI hecho) | En el mismo manuscrito | Pendiente | Por mapear |

El dataset del módulo neonatal no es MIMIC-IV y aún no está disponible. El manuscrito neonatal (un ensamble apilado sobre 20,982 admisiones neonatales) usa eliminación de valores atípicos por rango intercuartílico e imputación guiada por asimetría en su preprocesamiento. Mapearlo a E6 y E8 mostraría si esos pasos se ajustaron dentro de los pliegues de entrenamiento, algo que el resumen no dice; hay que comprobarlo antes de afirmar nada.

## 8. Esqueleto de carpetas

Esqueleto común propuesto, con el lugar en que está hoy cada proyecto. La división sigue las tres capas.

| Propuesto | Contiene | Proyecto materno hoy | Este proyecto hoy |
|---|---|---|---|
| `method/` | Cuadernos y código que leen la tabla del contrato: validación, apilado, métricas, sensibilidad, reporte | `notebooks/`, `libraries/functions.py` | `notebooks/` (exploratorios, por reconstruir) |
| `adapters/<dataset>/` | SQL o código que produce la tabla del contrato desde un dataset | `sql/01_load_mimic_iv_schema/`, `02_cohort_mortality/`, `03_cohort_smm/`, la base de `04_labels/`, `05_predictors/` | Usa las tablas del proyecto materno; nueva `sql/00_mimic_layer/` |
| `outcomes/<desenlace>/` | Ficha del desenlace, catálogo de códigos, script de etiqueta, set de sensibilidad | `04_labels/` | `sql/01_labels/` |
| `audit/<desenlace>/` | Scripts de la auditoría de conteos e informe | `06_audit_counts/`, `revision_audit_counts.md` | `sql/02_audit_counts/`, `count_audit_es.md` |
| `docs/` | Plan, TRIPOD+AI, listas de códigos, hojas de estrategia (E10) | `analysis_plan_notebooks.md`, `docs/` | `analysis_plan_es.md`, libro de seguimiento |

## 9. Decisiones de diseño abiertas del framework

| ID | Decisión | Opciones | Recomendación |
|---|---|---|---|
| FD1 | Dónde vive la capa de método | El repositorio materno sigue siendo el hogar del código compartido y los demás dependen de él (hoy); un monorepo con método, adaptadores y desenlaces; un repositorio de método aparte | Mantener la primera opción mientras el manuscrito materno esté en revisión; pasar a un monorepo después de la publicación |
| FD2 | Configuración del desenlace | Un archivo por desenlace (población, tabla de etiqueta, punto de predicción, ventana, conteos esperados, umbrales) que leen los scripts de auditoría y los cuadernos; valores escritos dentro de cada script | Un archivo por desenlace |
| FD3 | Columnas de unidad de análisis | Una tabla por adaptador de datos sin columnas de desenlace; columnas dentro de la tabla de etiqueta de cada desenlace | Una tabla por adaptador, sin columnas de desenlace, unida a la tabla de etiqueta en la auditoría; para MIMIC-IV `sql/00_mimic_layer/01_unit_of_analysis.sql` |
| FD4 | Nombres | Un patrón común para identificadores de desenlace, sufijo `*_v2` y tablas `<desenlace>_label_v2` | Adoptar el patrón ya usado (`fetal_death_label_v2`) |
| FD5 | Neonatal | El dataset no es MIMIC-IV y aún no está disponible; define el adaptador, el identificador de grupo (madre o recién nacido) y si aplica E4 | Decidir cuando llegue el dataset; el contrato está escrito para que nada de E7 a E11 dependa de esa elección |
| FD6 | Formato del contrato | Solo una especificación escrita; o una especificación más un script de verificación que valide la tabla de cualquier adaptador (columnas requeridas, tipos, una fila por unidad, conteos esperados) | Especificación más script de verificación |

## 10. Qué significa esto para la T17

La T17 es el adaptador de MIMIC-IV de la etapa E4. Las columnas de unidad de análisis (rango de la admisión dentro de la paciente, días desde la admisión anterior, primera admisión, cadena de embarazo a 30, 90 y 180 días) no dependen del desenlace, así que pasan a ser una tabla sin columnas de desenlace, `unit_of_analysis_v2`, escrita en `sql/00_mimic_layer/01_unit_of_analysis.sql` y válida solo para MIMIC-IV. Los conteos de eventos por unidad (ya medidos en Q-C4) salen de unirla con `fetal_death_label_v2` en la auditoría, y la misma tabla sirve para la morbilidad materna grave. Otro dataset necesitará su propia tabla con las mismas columnas del contrato (sección 3.1).

## 11. Encaje con el título de la tesis

Título: *Framework para la construcción de modelos predictivos que apoyen la formulación de estrategias de prevención y planes de acción en entidades de salud frente a las muertes maternas, perinatales y neonatales.*

| Elemento del título | Dónde lo cubre el framework | Qué falta |
|---|---|---|
| Framework para la construcción de modelos predictivos | E0 a E9 y E11 | Nada en este nivel |
| Muertes maternas, perinatales y neonatales | Módulo de desenlace con tres ranuras; la escalera de desenlaces explica por qué la muerte materna es un análisis de viabilidad y la morbilidad grave el sustituto que se modela | Mapeo del neonatal; la tesis debe decir con claridad qué desenlaces son muertes modeladas y cuáles son sustitutos |
| Estrategias de prevención y planes de acción | E10 (propuesta) | Aún no se aplica a ningún desenlace |
| En entidades de salud | E10, puntos 5 y 6: validación local y monitoreo, mediante un adaptador de datos escrito para los datos de la entidad | Aún no hay datos locales; MIMIC-IV es un solo hospital de EE. UU. |

Un framework extraído de dos casos es una generalización, no todavía una validación; el caso neonatal sería la tercera prueba.

*Confidencial: uso interno del proyecto de investigación.*
