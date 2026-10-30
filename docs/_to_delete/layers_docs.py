import io,re,collections
def rd(p): return io.open(p,encoding='utf-8',newline='').read()
def wr(p,s): io.open(p,'w',encoding='utf-8',newline='').write(s)
def sec(s,head,new):
    m=re.search(r'^'+re.escape(head)+r'.*?(?=^## |\Z)',s,re.S|re.M); assert m,head
    return s[:m.start()]+new.rstrip('\n')+'\n\n'+s[m.end():]
def sub1(s,pat,new,flags=re.M):
    assert len(re.findall(pat,s,flags))==1,(pat,len(re.findall(pat,s,flags))); return re.sub(pat,lambda m:new,s,flags=flags)
def ins_before(s,marker,text):
    assert s.count(marker)==1,marker; return s.replace(marker,text+marker)

EN=dict(
intro="Three layers and the gates between stages. The **method** layer is everything that does not depend on the dataset or the outcome: the stages, the validation, the stacked ensemble, the metrics and the reporting. The **data adapter** is the code that turns one dataset into the table the method reads (SQL for MIMIC-IV today; the neonatal dataset and the data of a health entity will need their own). The **outcome module** is the small set of choices that define one outcome (section 5). The **gates** are the decisions that must be recorded before the next stage starts. The method never reads a dataset directly: it reads the contract table of section 3.1.",
hdr="| Stage | Question it answers | Reused part (method, or the MIMIC-IV adapter) | Outcome parameter |",
s31="""## 3.1 Data contract

Whatever the dataset, an adapter has to deliver one table with one row per unit of analysis and these columns. Stages E4 to E11 run from that table only.

| Column | Meaning | MIMIC-IV adapter today |
|---|---|---|
| `unit_id` | Identifier of one unit of analysis | `hadm_id` |
| `group_id` | What must never be split between training and test | `subject_id` (patient) |
| `t0` | Time zero | Admission time |
| `t_pred` | Prediction point | `t0` + 6 h (perinatal), `t0` + 24 h (maternal) |
| `label_*` | Main label and sensitivity labels, as columns | `fetal_death_label_v2`, `label_admission_v2` |
| `x_*` with its availability time | Predictors and the moment each value became known | Predictors table of the 24-hour window rule |
| `period` | Calendar period or coding era, if the dataset has one | ICD version, anchor-year group |

Rules for any adapter: one row per unit; no personal identifier leaves the database; the counts reproduce the expected counts of the configuration; the same table feeds the audit and the models. If a dataset has no group identifier or no timestamps, the adapter must say so and the framework records the decision (for the neonatal dataset: the mother or the newborn as group, and whether E4 applies).

## 3.2 Which layer owns each stage

| Stage | Layer |
|---|---|
| E0 Governance | Method |
| E1 Universe and population | Data adapter |
| E2 Outcome definition | Outcome module, reading the adapter's code tables |
| E3 Count audit | Method structure (groups A–F), adapter queries |
| E4 Unit of analysis and overlap | Data adapter |
| E5 Prediction point and window | Outcome module, using the adapter's timestamps |
| E6 Predictors | Data adapter and outcome module |
| E7 Feasibility gate | Method |
| E8 Modelling, validation and metrics | Method |
| E9 Sensitivity and robustness | Method, plus the outcome's own set |
| E10 From prediction to prevention strategy | Method, outcome module and the health entity |
| E11 Reporting | Method |
""",
fold="""## 8. Folder skeleton

Proposed common skeleton, with where each project stands today. The split follows the three layers.

| Proposed | Holds | Maternal project today | This project today |
|---|---|---|---|
| `method/` | Notebooks and code that read the contract table: validation, stacking, metrics, sensitivity, reporting | `notebooks/`, `libraries/functions.py` | `notebooks/` (exploratory, to be rebuilt) |
| `adapters/<dataset>/` | SQL or code that produces the contract table from one dataset | `sql/01_load_mimic_iv_schema/`, `02_cohort_mortality/`, `03_cohort_smm/`, the base of `04_labels/`, `05_predictors/` | Uses the maternal tables; new `sql/00_mimic_layer/` |
| `outcomes/<outcome>/` | Outcome card, code catalogue, label script, sensitivity set | `04_labels/` | `sql/01_labels/` |
| `audit/<outcome>/` | Count audit scripts and write-up | `06_audit_counts/`, `revision_audit_counts.md` | `sql/02_audit_counts/`, `count_audit.md` |
| `docs/` | Plan, TRIPOD+AI, code lists, strategy sheets (E10) | `analysis_plan_notebooks.md`, `docs/` | `analysis_plan.md`, workbook |
""",
dec="""## 9. Open design decisions for the framework

| ID | Decision | Options | Recommendation |
|---|---|---|---|
| FD1 | Where the method layer lives | The maternal repository stays the home of the shared code and the others depend on it (today); one monorepo with method, adapters and outcomes; a separate method repository | Keep the first option while the maternal manuscript is in revision; move to a monorepo after publication |
| FD2 | Outcome configuration | One file per outcome (population, label table, prediction point, window, expected counts, thresholds) read by the audit scripts and notebooks; values written inside each script | One file per outcome |
| FD3 | Unit-of-analysis columns | A table per dataset adapter with no outcome columns; columns inside each outcome's label table | A table per adapter, without outcome columns, joined to the label table in the audit; for MIMIC-IV `sql/00_mimic_layer/01_unit_of_analysis.sql` |
| FD4 | Names | A common pattern for outcome identifiers, `*_v2` suffix and `<outcome>_label_v2` tables | Adopt the pattern already used (`fetal_death_label_v2`) |
| FD5 | Neonatal | The dataset is not MIMIC-IV and is not available yet; it defines the adapter, the group identifier (mother or newborn) and whether E4 applies | Decide when the dataset arrives; the contract is written so that nothing in E7 to E11 depends on that choice |
| FD6 | Contract format | A written specification only; or a specification plus a check script that validates any adapter's table (required columns, types, one row per unit, expected counts) | Specification plus check script |
""",
t17="""## 10. What this means for T17

T17 is the MIMIC-IV adapter of stage E4. The unit-of-analysis columns (admission rank within the patient, days since the previous admission, first admission, pregnancy chain at 30, 90 and 180 days) do not depend on the outcome, so they become a table with no outcome columns, `unit_of_analysis_v2`, written in `sql/00_mimic_layer/01_unit_of_analysis.sql` and valid only for MIMIC-IV. The event counts per unit (already measured in Q-C4) come from joining it with `fetal_death_label_v2` in the audit, and the same table serves severe maternal morbidity. Another dataset will need its own table with the same contract columns (section 3.1).
""",
card_row="| Dataset | MIMIC-IV | MIMIC-IV | MIMIC-IV | Not MIMIC-IV; not available yet |\n",
neo_note="The dataset for the neonatal module is not MIMIC-IV and is not available yet. ",
fit_old="| In health entities | E10 items 5 and 6: local validation and monitoring | No local data yet; MIMIC-IV is a single US hospital |",
fit_new="| In health entities | E10 items 5 and 6: local validation and monitoring, through a data adapter written for the entity's data | No local data yet; MIMIC-IV is a single US hospital |",
)
ES=dict(
intro="Tres capas y las puertas entre etapas. La capa de **método** es todo lo que no depende del dataset ni del desenlace: las etapas, la validación, el ensamble apilado, las métricas y el reporte. El **adaptador de datos** es el código que convierte un dataset en la tabla que lee el método (SQL para MIMIC-IV hoy; el dataset neonatal y los datos de una entidad de salud necesitarán el suyo). El **módulo de desenlace** es el pequeño conjunto de elecciones que definen un desenlace (sección 5). Las **puertas** son las decisiones que deben quedar registradas antes de que empiece la siguiente etapa. El método nunca lee un dataset directamente: lee la tabla del contrato de la sección 3.1.",
hdr="| Etapa | Pregunta que responde | Parte que se reutiliza (método o adaptador de MIMIC-IV) | Parámetro del desenlace |",
s31="""## 3.1 Contrato de datos

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
""",
fold="""## 8. Esqueleto de carpetas

Esqueleto común propuesto, con el lugar en que está hoy cada proyecto. La división sigue las tres capas.

| Propuesto | Contiene | Proyecto materno hoy | Este proyecto hoy |
|---|---|---|---|
| `method/` | Cuadernos y código que leen la tabla del contrato: validación, apilado, métricas, sensibilidad, reporte | `notebooks/`, `libraries/functions.py` | `notebooks/` (exploratorios, por reconstruir) |
| `adapters/<dataset>/` | SQL o código que produce la tabla del contrato desde un dataset | `sql/01_load_mimic_iv_schema/`, `02_cohort_mortality/`, `03_cohort_smm/`, la base de `04_labels/`, `05_predictors/` | Usa las tablas del proyecto materno; nueva `sql/00_mimic_layer/` |
| `outcomes/<desenlace>/` | Ficha del desenlace, catálogo de códigos, script de etiqueta, set de sensibilidad | `04_labels/` | `sql/01_labels/` |
| `audit/<desenlace>/` | Scripts de la auditoría de conteos e informe | `06_audit_counts/`, `revision_audit_counts.md` | `sql/02_audit_counts/`, `count_audit_es.md` |
| `docs/` | Plan, TRIPOD+AI, listas de códigos, hojas de estrategia (E10) | `analysis_plan_notebooks.md`, `docs/` | `analysis_plan_es.md`, libro de seguimiento |
""",
dec="""## 9. Decisiones de diseño abiertas del framework

| ID | Decisión | Opciones | Recomendación |
|---|---|---|---|
| FD1 | Dónde vive la capa de método | El repositorio materno sigue siendo el hogar del código compartido y los demás dependen de él (hoy); un monorepo con método, adaptadores y desenlaces; un repositorio de método aparte | Mantener la primera opción mientras el manuscrito materno esté en revisión; pasar a un monorepo después de la publicación |
| FD2 | Configuración del desenlace | Un archivo por desenlace (población, tabla de etiqueta, punto de predicción, ventana, conteos esperados, umbrales) que leen los scripts de auditoría y los cuadernos; valores escritos dentro de cada script | Un archivo por desenlace |
| FD3 | Columnas de unidad de análisis | Una tabla por adaptador de datos sin columnas de desenlace; columnas dentro de la tabla de etiqueta de cada desenlace | Una tabla por adaptador, sin columnas de desenlace, unida a la tabla de etiqueta en la auditoría; para MIMIC-IV `sql/00_mimic_layer/01_unit_of_analysis.sql` |
| FD4 | Nombres | Un patrón común para identificadores de desenlace, sufijo `*_v2` y tablas `<desenlace>_label_v2` | Adoptar el patrón ya usado (`fetal_death_label_v2`) |
| FD5 | Neonatal | El dataset no es MIMIC-IV y aún no está disponible; define el adaptador, el identificador de grupo (madre o recién nacido) y si aplica E4 | Decidir cuando llegue el dataset; el contrato está escrito para que nada de E7 a E11 dependa de esa elección |
| FD6 | Formato del contrato | Solo una especificación escrita; o una especificación más un script de verificación que valide la tabla de cualquier adaptador (columnas requeridas, tipos, una fila por unidad, conteos esperados) | Especificación más script de verificación |
""",
t17="""## 10. Qué significa esto para la T17

La T17 es el adaptador de MIMIC-IV de la etapa E4. Las columnas de unidad de análisis (rango de la admisión dentro de la paciente, días desde la admisión anterior, primera admisión, cadena de embarazo a 30, 90 y 180 días) no dependen del desenlace, así que pasan a ser una tabla sin columnas de desenlace, `unit_of_analysis_v2`, escrita en `sql/00_mimic_layer/01_unit_of_analysis.sql` y válida solo para MIMIC-IV. Los conteos de eventos por unidad (ya medidos en Q-C4) salen de unirla con `fetal_death_label_v2` en la auditoría, y la misma tabla sirve para la morbilidad materna grave. Otro dataset necesitará su propia tabla con las mismas columnas del contrato (sección 3.1).
""",
card_row="| Dataset | MIMIC-IV | MIMIC-IV | MIMIC-IV | No es MIMIC-IV; aún no disponible |\n",
neo_note="El dataset del módulo neonatal no es MIMIC-IV y aún no está disponible. ",
fit_old="| En entidades de salud | E10, puntos 5 y 6: validación local y monitoreo | Aún no hay datos locales; MIMIC-IV es un solo hospital de EE. UU. |",
fit_new="| En entidades de salud | E10, puntos 5 y 6: validación local y monitoreo, mediante un adaptador de datos escrito para los datos de la entidad | Aún no hay datos locales; MIMIC-IV es un solo hospital de EE. UU. |",
)
def apply(p,T,intro_pat,hdr_pat,sec8,sec9,sec10,card_anchor,neo_anchor):
    s=rd(p)
    s=sub1(s,intro_pat,T['intro'])
    s=sub1(s,hdr_pat,T['hdr'])
    # insert 3.1/3.2 before section 4
    s=ins_before(s,'## 4. ',T['s31']) if s.count('## 4. ')==1 else None
    s=sec(s,sec8,T['fold']); s=sec(s,sec9,T['dec']); s=sec(s,sec10,T['t17'])
    s=ins_before(s,card_anchor,T['card_row'])
    s=ins_before(s,neo_anchor,T['neo_note'])
    s=s.replace(T['fit_old'],T['fit_new']); assert T['fit_new'] in s
    wr(p,s)
import os
os.chdir(os.path.expanduser('~/mnt/Tesis/PerinatalMortality_MIMIC-IV'))
apply('framework.md',EN,r'^Three parts\..*$',r'^\| Stage \| Question it answers \| Core \(reused as is\) \| Outcome parameter \|$','## 8. Folder skeleton','## 9. Open design decisions','## 10. What this means for T17','| Status |','The neonatal manuscript (a stacked')
apply('framework_es.md',ES,r'^Tres partes\..*$',r'^\| Etapa \| Pregunta que responde \| Núcleo \(se reutiliza tal cual\) \| Parámetro del desenlace \|$','## 8. Esqueleto de carpetas','## 9. Decisiones de diseño abiertas','## 10. Qué significa esto para la T17','| Estado |','El manuscrito neonatal (un ensamble')
a=rd('framework.md'); b=rd('framework_es.md')
num=lambda s: collections.Counter(re.findall(r'\d[\d,.]*\d|\d',s))
ca,cb=num(a),num(b)
print('EN only',{k:v-cb.get(k,0) for k,v in ca.items() if v>cb.get(k,0)}); print('ES only',{k:v-ca.get(k,0) for k,v in cb.items() if v>ca.get(k,0)})
print(len(re.findall(r'^#+ ',a,re.M)),len(re.findall(r'^#+ ',b,re.M)),a.count('\n|'),b.count('\n|'))
