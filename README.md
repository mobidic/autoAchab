# autoAchab
script to automatically launch captainAchab MobiDL WDL workflow

**The bash script and conf script should be placed in MobiDL Dir**

## How To : prepare inputs for autoAchab and get results

### What are we talking about

CaptainAchab is a workflow which takes a raw VCF file as input and performs several steps to produce an annotated Excel file. Please refer to the [github page](https://github.com/mobidic/Captain-ACHAB).

### Goals

autoAchab is a script which goal is to properly and easily launch captainAchab workflows on many samples, sequentially. In a word, you put the right filesat the right place, and autoAchab handles the dirt for you.

### Nice, but How?

Simply provide in the input directory the VCF file, the disease.txt file for phenolyzer and a captainAchab_inputs.json file ready for cromwell execution of the workflow, then get your results in the output dir.

All configuration is made through the autoAchab.conf file, which should be self-explanatory.

The host machine should be able to run a full captainAchab worflow (see link above). 



