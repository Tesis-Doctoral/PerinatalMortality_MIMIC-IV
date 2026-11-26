# Auditoría de conteos — información disponible antes del ingreso (modelo prenatal)

Ejecutada el 18/11/2026 con los scripts de `sql/03_antenatal/` (población y etiqueta, tarea A0) y `sql/03_antenatal/03_prior_information_es.sql` (información previa, tarea A1); las versiones en inglés no llevan el sufijo `_es`. Versión en inglés: [`count_audit_antenatal.md`](count_audit_antenatal.md).

**Etapa del framework:** E4 (auditoría de conteos). Sus resultados fijan los predictores (E7) y los parámetros candidatos antes de la puerta de tamaño de muestra (P3).

Todas las cifras son conteos agregados. No se publica ningún `subject_id`, `hadm_id` ni fila a nivel de paciente, y los conteos de 1 a 4 se muestran como "<5". Las propuestas de este documento se registran en la ficha del desenlace ([`docs/outcome_card_antenatal_es.md`](docs/outcome_card_antenatal_es.md)) antes de ajustar cualquier modelo.

## 1. Qué se quería saber

El modelo prenatal solo puede usar lo que se sabía de la mujer **antes** del ingreso para el parto. Antes de construirlo había que responder tres preguntas:

1. ¿Cuántas pacientes tienen alguna información previa? Si casi nadie la tiene, el modelo no es viable.
2. ¿Qué información hay, con qué frecuencia y qué tan reciente es?
3. Con eso, ¿qué predictores entran al modelo?

## 2. Cómo se midió

- **Población:** hospitalizaciones de parto, más las admisiones con un código de mortinato que no quedaron marcadas como parto: 19.440 admisiones de 13.735 pacientes.
- **Desenlace:** muerte fetal con definición estricta, es decir, un código de muerte fetal de todo el embarazo (CIE-10-CM O36.4, Z37.1, Z37.4, Z37.7; CIE-9-CM 656.4, V27.1, V27.4, V27.7): 129 eventos (0,66%). La etiqueta está en la tabla `antenatal_fetal_death_label`, con una fila por admisión (`sql/03_antenatal/`).
- **Ventana de información:** todo lo registrado **al menos 7 días antes** del ingreso (margen principal). Como sensibilidad se usaron 1 y 30 días. El margen evita usar información de una consulta en la que ya se había detectado la muerte fetal.
- **Fuentes:**
  - hospitalizaciones anteriores en el mismo hospital (sus diagnósticos y procedimientos);
  - mediciones ambulatorias (tabla `omr`: peso, presión arterial, IMC, talla);
  - laboratorios ambulatorios (`labevents` sin hospitalización asociada).
- **Regla contra la selección por desenlace:** solo las consultas de disponibilidad por bloque (Q-A1 a Q-A3) separan eventos y no eventos, porque deciden si el modelo es posible. La frecuencia de cada antecedente o medición (Q-A4 a Q-A7) se muestra solo para toda la población. Así ningún predictor se elige por su asociación con la muerte fetal.
- **Ajustes al script durante la ejecución:**
  - en esta base, `omr.chartdate` es fecha y hora, así que se convirtió a fecha;
  - la columna de raza se llama `ethnicity`, como en las cargas anteriores de MIMIC-IV.

## 3. Población y etiqueta (puerta de definición P1)

Antes de medir la información previa se comprobó que la población y la etiqueta se construyen igual y reproducen los conteos de referencia. Es la condición de la puerta P1: población, unidad y definición fijas, y conteos reproducibles. Scripts: `sql/03_antenatal/01_obstetric_universe_es.sql` y `02_fetal_death_label_es.sql`.

### Q-U1. Universo obstétrico y población

| Admisiones obstétricas | Pacientes | Hospitalizaciones de parto | Con código de mortinato | Población del modelo |
|---|---|---|---|---|
| 25.736 | 15.084 | 19.425 | 124 | 19.440 |

**Qué significa.** El universo obstétrico son las admisiones de mujeres de 12 a 55 años con al menos un diagnóstico de embarazo, parto o puerperio. De ellas, 19.425 son hospitalizaciones de parto. De los 124 códigos de mortinato, 109 están dentro de partos y 15 quedan fuera de la marca de parto. Esas 15 se suman a la población: 19.425 + 15 = 19.440.

### Q-U2. Población por era de codificación

| Era | Partos | Código de mortinato sin marca de parto |
|---|---|---|
| CIE-10 | 8.883 | 10 |
| CIE-9 | 10.542 | 5 |

**Qué significa.** Las 15 admisiones con mortinato fuera de la marca de parto tienen también un código de aborto, que es la razón por la que la marca las excluye. Se mantienen en la población porque la muerte fetal es el desenlace. La población se reparte casi por mitades entre las dos eras de codificación.

### Q-L1. Catálogo de códigos de muerte fetal

| Nivel | CIE-9 | CIE-10 |
|---|---|---|
| Estricto | 4 | 4 |
| Parcial | 2 | 3 |
| Excluido | 3 | 2 |

**Qué significa.** El catálogo tiene los 18 patrones previstos.
- **Estrictos:** muerte fetal de todo el embarazo (O36.4, Z37.1, Z37.4, Z37.7; 656.4, V27.1, V27.4, V27.7).
- **Parciales:** embarazos múltiples en los que murió algún feto.
- **Excluidos:** la muerte fetal temprana (antes de 20 o 22 semanas) y los códigos del registro del recién nacido. Se listan solo para auditoría.

### Q-L2. Conteos de referencia de la población

| Admisiones | Pacientes | Eventos estrictos | Eventos con parciales |
|---|---|---|---|
| 19.440 | 13.735 | 129 | 142 |

**Qué significa.** La población y el desenlace coinciden con los conteos de referencia. **La puerta P1 queda pasada.**

### Q-L3. Tamaño de cada definición de la etiqueta

| Definición | Eventos | Uso |
|---|---|---|
| Estricta, cualquier edad gestacional | 129 | Modelo principal |
| Estricta más parcial | 142 | Sensibilidad |
| Estricta sin código de pérdida temprana | 119 | Sensibilidad |
| Estricta con 22 semanas o más | 55 | Sensibilidad (solo CIE-10) |
| Estricta con 28 semanas o más | 37 | Sensibilidad (solo CIE-10) |
| Estricta sin semanas de gestación | 61 | Se reportan aparte |
| Estricta con código del registro del recién nacido | 0 | Control |

**Qué significa.**
1. Las semanas de gestación solo existen en CIE-10. Por eso las definiciones de 22 y 28 semanas tienen pocos eventos (55 y 37) y servirán para ver la dirección del resultado, no para un modelo propio.
2. Ningún evento usa un código del registro del recién nacido, así que la etiqueta solo usa el registro de la madre.

## 4. Información disponible antes del ingreso (Q-A0 a Q-A7)

### Q-A0. Verificación de la población

| Admisiones | Pacientes | Eventos estrictos | Eventos con parciales |
|---|---|---|---|
| 19.440 | 13.735 | 129 | 142 |

**Qué significa.** Las cifras coinciden con los conteos de referencia de la población y de la etiqueta. La base, la población y la etiqueta están bien conectadas.

**Para el modelo.** Se fija como conteo esperado: cualquier corrida con otra población se detiene (puerta P1).

### Q-A1. ¿Cuántas tienen información previa? (el conteo de factibilidad)

| Margen | Grupo | Admisiones | Alguna información | % | Hospitalización anterior | Hospitalización obstétrica anterior | Mediciones ambulatorias | Laboratorios ambulatorios |
|---|---|---|---|---|---|---|---|---|
| 1 día | Eventos estrictos | 129 | 100 | 77,5 | 50 | 48 | 87 | 80 |
| 1 día | Solo parciales | 13 | 11 | 84,6 | 7 | 7 | 10 | 10 |
| 1 día | No eventos | 19.298 | 17.174 | 89,0 | 8.508 | 7.592 | 14.192 | 14.102 |
| **7 días** | **Eventos estrictos** | **129** | **99** | **76,7** | **49** | **47** | **86** | **79** |
| 7 días | Solo parciales | 13 | 11 | 84,6 | 7 | 7 | 10 | 10 |
| **7 días** | **No eventos** | **19.298** | **17.056** | **88,4** | **8.369** | **7.438** | **14.151** | **13.965** |
| 30 días | Eventos estrictos | 129 | 97 | 75,2 | 47 | 44 | 84 | 78 |
| 30 días | Solo parciales | 13 | 11 | 84,6 | 7 | 7 | 10 | 10 |
| 30 días | No eventos | 19.298 | 16.811 | 87,1 | 8.031 | 7.059 | 14.004 | 13.721 |

Las columnas de fuentes no se suman: una paciente puede tener varias fuentes a la vez.

**Qué significa.**
1. **El modelo es viable.** Tres de cada cuatro mujeres con muerte fetal (99 de 129) tienen información previa al ingreso.
2. **Las mediciones ambulatorias son la fuente más común** (67% de los eventos), por encima de las hospitalizaciones anteriores (38%).
3. **El margen casi no cambia nada.** Entre 1 y 30 días se pierden apenas 3 eventos con información, así que el resultado no dependerá de esa elección.
4. **Las mujeres con muerte fetal tienen algo menos de información** (77% frente a 88%). Puede reflejar menos control prenatal en este hospital, que es un factor de riesgo conocido, o que llegaron desde otro lugar.

**Para el modelo.**
- Margen principal de 7 días; 1 y 30 días como sensibilidad.
- Cada bloque lleva un indicador de "hay información", porque no tener registro no significa no tener la condición.
- Análisis de sensibilidad nuevo: repetir el modelo **solo en las pacientes con alguna información previa** (99 eventos), para comprobar que el resultado no depende de quién tiene historia y quién no.

### Q-A2. Información previa según la época (margen de 7 días)

El grupo de años es un grupo asignado a cada paciente por MIMIC-IV (las fechas están desplazadas). Indica aproximadamente cuándo empezó a aparecer en el hospital, no el año del parto.

| Era CIE | Grupo de años | Admisiones | Con información | % | Eventos estrictos | Eventos con información |
|---|---|---|---|---|---|---|
| CIE-10 | 2008–2010 | 1.533 | 1.497 | 97,7 | 12 | 12 |
| CIE-10 | 2011–2013 | 1.512 | 1.480 | 97,9 | 10 | 10 |
| CIE-10 | 2014–2016 | 2.561 | 2.342 | 91,4 | 16 | 15 |
| CIE-10 | 2017–2019 | 2.353 | 2.009 | 85,4 | 22 | 11 |
| CIE-10 | 2020–2022 | 934 | 765 | 81,9 | 11 | 9 |
| CIE-9 | 2008–2010 | 6.700 | 5.910 | 88,2 | 34 | 30 |
| CIE-9 | 2011–2013 | 2.826 | 2.417 | 85,5 | 17 | 9 |
| CIE-9 | 2014–2016 | 1.020 | 746 | 73,1 | 7 | <5 |
| CIE-9 | 2017–2019 | <5 | 0 | — | 0 | 0 |

**Qué significa.**
1. **Cuanto más antigua es la paciente en el hospital, más información previa tiene.** La cobertura baja de 98% a 82% en CIE-10 y de 88% a 73% en CIE-9, porque las de grupos recientes tuvieron menos tiempo para acumular registros.
2. **En los eventos el efecto es más fuerte.** En los grupos recientes, cerca de la mitad de las mujeres con muerte fetal tiene información previa.

**Para el modelo.**
- Afecta al criterio **C4 (estabilidad en el tiempo)**. La validación temporal entrena con épocas de mucha historia y prueba con épocas de menos historia. El desempeño puede bajar y los indicadores de "hay información" pueden significar cosas distintas según la época.
- Se reporta la calibración por período, se mantiene la sensibilidad "solo pacientes con información previa" y se declara como limitación conocida antes de modelar.

### Q-A3. Hospitalizaciones anteriores: cuántas y hace cuánto (margen de 7 días)

| Grupo | Admisiones | Ninguna | Una | Dos o tres | Cuatro o más | Última hace ≤ 90 días | 91–365 días | > 1 año |
|---|---|---|---|---|---|---|---|---|
| Eventos estrictos | 129 | 80 | 22 | 20 | 7 | 12 | <5 | 34 |
| Solo parciales | 13 | 6 | <5 | <5 | 0 | <5 | 0 | <5 |
| No eventos | 19.298 | 10.929 | 5.156 | 2.636 | 577 | 1.513 | 870 | 5.986 |
| Total | 19.440 | 11.015 | 5.181 | 2.660 | 584 | 1.528 | 873 | 6.024 |

**Qué significa.**
1. **Seis de cada diez mujeres no tienen hospitalizaciones anteriores** en este hospital. Para ellas, los antecedentes de diagnósticos estarán vacíos.
2. **La mayoría de las hospitalizaciones anteriores fueron hace más de un año** (69–72%), es decir, en embarazos anteriores. Esta fuente aporta sobre todo **antecedentes obstétricos**: cesárea, preeclampsia, parto pretérmino u óbito en otro embarazo.
3. **Las de menos de 90 días** probablemente son del embarazo actual (amenaza de parto pretérmino, hipertensión, sangrado). Son pocas, pero reflejan complicaciones del embarazo en curso.

**Para el modelo.**
- Dos indicadores: **alguna hospitalización anterior** y **hospitalización en los 90 días previos**. El segundo es más útil que los días desde el último egreso, porque distingue el embarazo actual de los anteriores.

### Q-A4. Antecedentes en hospitalizaciones anteriores (margen de 7 días; solo toda la población)

El porcentaje "con historia" se calcula sobre las 8.425 admisiones con alguna hospitalización anterior.

| Antecedente | Admisiones | % de la población | % de las que tienen historia |
|---|---|---|---|
| Cesárea anterior | 1.670 | 8,59 | 19,82 |
| Trastorno hipertensivo en embarazo anterior | 989 | 5,09 | 11,74 |
| Enfermedad tiroidea | 728 | 3,74 | 8,64 |
| Obesidad (código) | 669 | 3,44 | 7,94 |
| Hipertensión crónica | 472 | 2,43 | 5,60 |
| Tabaco, alcohol o drogas | 457 | 2,35 | 5,42 |
| Parto pretérmino anterior | 419 | 2,16 | 4,97 |
| Diabetes gestacional anterior | 418 | 2,15 | 4,96 |
| Diabetes pregestacional | 267 | 1,37 | 3,17 |
| Lupus, antifosfolípido o trombofilia | 91 | 0,47 | 1,08 |
| Muerte fetal anterior | 52 | 0,27 | 0,62 |
| VIH o sífilis | 30 | 0,15 | 0,36 |
| Enfermedad renal crónica | 27 | 0,14 | 0,32 |

**Qué significa.**
1. Los antecedentes frecuentes (más de 1% de la población) tienen suficientes casos para que el modelo aprenda de ellos.
2. Los raros (menos de 1%) aportan como mucho uno o dos eventos cada uno. El modelo no puede aprender algo estable de ellos, y cada uno gastaría uno de los 17 a 25 parámetros que soportan los datos (sección 5).
3. La muerte fetal anterior es el factor de riesgo más fuerte en la literatura, pero aquí es muy rara (52 admisiones).

**Para el modelo** (decidido solo con estas frecuencias y razones clínicas, sin mirar el desenlace).
- **Se quedan solos:**
  - cesárea anterior;
  - trastorno hipertensivo en embarazo anterior;
  - hipertensión crónica;
  - diabetes pregestacional;
  - diabetes gestacional anterior;
  - tabaco, alcohol o drogas;
  - enfermedad tiroidea.
- **Compuesto "resultado adverso en embarazo anterior":** muerte fetal o parto pretérmino anterior, unas 460 admisiones (2,4%). Así no se pierde el antecedente de óbito.
- **Compuesto "otra condición crónica de alto riesgo":** lupus, antifosfolípido o trombofilia; VIH o sífilis; enfermedad renal crónica. Son unas 150 admisiones (0,8%).
- **Obesidad por código:** se descarta en favor del IMC medido (Q-A5).
- Las listas de códigos son provisionales y se verifican antes de construir la tabla de predictores.

### Q-A5. Mediciones ambulatorias (margen de 7 días; solo toda la población)

| Medición | Admisiones con valor | % de la población | Valor en el último año | Mediana de días antes del ingreso |
|---|---|---|---|---|
| Peso (Weight, Lbs) | 13.586 | 69,9 | 11.124 | 13 |
| Presión arterial | 13.267 | 68,2 | 12.161 | 12 |
| IMC (BMI, kg/m2) | 10.195 | 52,4 | 7.950 | 14 |
| Talla (Height, Inches) | 9.227 | 47,5 | 5.368 | 267 |
| IMC (otro nombre: BMI) | 757 | 3,9 | 730 | 62 |
| Peso (otro nombre: Weight) | 124 | 0,6 | 110 | 85 |
| Presión arterial sentada | 66 | 0,3 | 29 | 518 |
| Presión arterial de pie (1 min) | 52 | 0,3 | 22 | 518 |
| Presión arterial acostada | 49 | 0,3 | 19 | 532 |
| Presión arterial de pie | 10 | 0,1 | <5 | 1.139 |
| Presión arterial de pie (3 min) | 7 | 0,0 | <5 | 305 |
| Talla (otro nombre: Height) | 6 | 0,0 | 6 | 207 |

**Qué significa.**
1. **Es el bloque más valioso.** Siete de cada diez mujeres tienen peso y presión arterial, y la mitad de esos valores se tomó **menos de dos semanas antes del parto**. Son mediciones de los controles prenatales del embarazo actual.
2. **La presión arterial es el predictor más prometedor.** La hipertensión del embarazo es una de las causas principales de muerte fetal, y aquí está la presión medida, no solo un código.
3. El IMC tiene menos cobertura que el peso, pero puede calcularse con el peso y la talla. La talla casi no cambia, así que sirve aunque sea antigua.
4. El IMC de un control prenatal incluye la ganancia de peso del embarazo; no es el IMC previo al embarazo.
5. Las filas con otros nombres son las mismas mediciones registradas por otro sistema y se unen con la principal.

**Para el modelo.**
- **Ventana del embarazo actual:** solo valores tomados entre 280 y 7 días antes del ingreso. Si no hay valor en esa ventana, queda faltante con su indicador.
- **Presión arterial:**
  - última sistólica;
  - última diastólica;
  - indicador de **alguna presión de 140/90 o más** en la ventana.
- **IMC:** el último registrado; si falta, calculado con el último peso y cualquier talla disponible.
- **Obesidad por código:** se descarta.

### Q-A6. Laboratorios ambulatorios (margen de 7 días; solo toda la población)

| Examen | Admisiones con valor | % de la población | Valor en el último año | Mediana de días antes del ingreso |
|---|---|---|---|---|
| Hemoglobina | 13.453 | 69,2 | 11.669 | 85 |
| Creatinina | 9.790 | 50,4 | 6.460 | 200 |
| Hemoglobina glicosilada (A1c) | 3.349 | 17,2 | 2.076 | 239 |
| Cualquier otro examen | 14.054 | 72,3 | 12.471 | 59 |

**Qué significa.**
1. **La hemoglobina es la mejor de este bloque.** Tiene buena cobertura (69%), y la mediana de 85 días coincide con el hemograma de rutina del tercer trimestre. La anemia materna es un factor de riesgo de muerte fetal.
2. **La creatinina es antigua** (mediana de 200 días) y en mujeres jóvenes suele ser normal.
3. **La hemoglobina glicosilada se pide de forma selectiva**, casi siempre ante sospecha de diabetes. Que se haya pedido ya dice algo de la paciente.
4. "Cualquier otro examen" refleja que la paciente se controló en este hospital.

**Para el modelo.**
- **Se queda:** última hemoglobina en la ventana del embarazo actual.
- **Se descartan:**
  - la creatinina, porque aporta poco y la enfermedad renal ya está en el compuesto de condiciones crónicas;
  - la hemoglobina glicosilada, porque se pide de forma selectiva y la diabetes ya está cubierta por los antecedentes.
- **Indicador único "tuvo control prenatal en este hospital"**, que reúne mediciones y laboratorios ambulatorios. Las dos coberturas son casi iguales (70–72%) y miden lo mismo.

### Q-A7. Variables de registro del ingreso (solo toda la población)

| Admisiones | Estado civil faltante | Seguro faltante u "Other" | Idioma faltante | Raza o etnia desconocida o no declarada |
|---|---|---|---|---|
| 19.440 | 385 (2,0%) | 441 (2,3%) | 30 (0,2%) | 928 (4,8%) |

**Qué significa.** Las variables de registro están casi completas. Se toman al llegar y no dependen de cómo se presentó la paciente, así que pueden usarse.

**Para el modelo.** El tipo y el lugar de admisión siguen excluidos: reflejan cómo llegó la paciente, y eso lo puede causar la propia muerte fetal.

| Variable | Categorías | Parámetros |
|---|---|---|
| Edad | continua | 1 |
| Raza o etnia | blanca, negra, hispana, asiática, otra o desconocida | 4 |
| Seguro | Medicaid, privado, Medicare u otro o faltante | 2 |
| Idioma | inglés, otro o faltante | 1 |
| Estado civil | casada, no casada, faltante | 2 |

## 5. Lo que la auditoría deja para el modelo

### Parámetros que soportan los datos

Con 19.440 admisiones y 129 eventos (prevalencia de 0,66%), los criterios de Riley et al. soportan unos **17 parámetros** si el R² de Cox-Snell del modelo es el 10% de su máximo, y unos **25** si es el 15%. Es una estimación previa: la puerta de tamaño de muestra (P3) se decide con el R² observado.

### Lista de predictores propuesta (unos 27 parámetros)

| Bloque | Predictores | Parámetros |
|---|---|---|
| Registro | edad, raza o etnia, seguro, idioma, estado civil | 10 |
| Historia de atenciones | alguna hospitalización anterior; hospitalización en los 90 días previos | 2 |
| Antecedentes | cesárea; trastorno hipertensivo en embarazo anterior; hipertensión crónica; diabetes pregestacional; diabetes gestacional anterior; tabaco, alcohol o drogas; enfermedad tiroidea; resultado adverso en embarazo anterior; otra condición crónica de alto riesgo | 9 |
| Controles del embarazo actual | última sistólica; última diastólica; alguna presión de 140/90 o más; último IMC | 4 |
| Laboratorio del embarazo actual | última hemoglobina | 1 |
| Indicador | tuvo control prenatal en este hospital | 1 |
| **Total** | | **27** |

### Conjunto reducido (17 parámetros), fijado antes de cualquier modelo

Se usa si la puerta de tamaño de muestra (P3) no se pasa con los 27 parámetros:
- edad;
- raza o etnia (4 parámetros);
- Medicaid;
- inglés;
- casada;
- tuvo control prenatal en este hospital;
- última sistólica;
- presión elevada;
- IMC;
- hemoglobina;
- antecedente hipertensivo (crónico o en embarazo anterior);
- diabetes (pregestacional o gestacional anterior);
- resultado adverso en embarazo anterior.

Nunca se elige por la asociación de los predictores con el desenlace.

### Análisis de sensibilidad que agrega la auditoría

| Análisis | Pregunta |
|---|---|
| Márgenes de 1 y 30 días | ¿El resultado depende del margen elegido? |
| Solo pacientes con alguna información previa | ¿El resultado depende de quién tiene historia en el hospital? |
| Calibración por período | ¿El modelo funciona igual en épocas con menos historia (C4)? |

### Lo que queda pendiente antes de construir la tabla de predictores

1. Verificar las listas de códigos de los antecedentes (son provisionales).
2. Separar la sistólica y la diastólica del texto de presión arterial ("120/80") y fijar límites de plausibilidad para presión, IMC y hemoglobina.
3. Unir las mediciones registradas con nombres distintos (BMI, Weight, Height y las variantes de presión arterial).

*Confidencial: uso interno del proyecto de investigación.*
