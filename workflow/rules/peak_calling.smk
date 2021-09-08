## HELPER FUNCTIONS inherited from parent SnakeFile:
# samples(pep)
# lookup_sample_metadata(sample, key, pep)

# GLOBAL CONSTANTS inherited from parent Snakefile:
# RES - resolution of coverage
# WITHIN - normalization to perform within samples
 
rule clean_peak_calling:
    shell:
        "rm -fr results/peak_calling"


def determine_peak_calling_files(config, pep):
    outfiles = []
    for model in lookup_in_config(config, ["peak_calling"], []):
        peak_caller = lookup_in_config(config, ["peak_calling", model, "peak_caller"], 
        err = "Need peak caller specified for peak_caller model %s in config file. I.e. \npeak_calling:\n\t%s:\n\t\tpeak_caller: 'macs2'"%(model,model))
        these_samples = filter_samples(pep, \
        lookup_in_config(config, ["peak_calling", model, "filter"], "not input_sample.isnull()"))
        if peak_caller == "macs2":
            for sample in these_samples:
                outfiles.append("results/peak_calling/%s/macs2/%s_peaks.xls"%(model, sample))
        if peak_caller == "cmarrt":
            for sample in these_samples:
                outfiles.append("results/peak_calling/%s/cmarrt/%s.narrowPeak"%(model,sample))
    return outfiles

rule run_peak_calling:
    input:
        determine_peak_calling_files(config, pep)


def determine_cmarrt_input(sample, model, config, pep):
   file_sig = lookup_in_config(config, ["peak_calling", model, "filesignature"], 
   "results/coverage_and_norm/bwtools_compare/%s_BPM_subinp.bw")
   return file_sig%(sample)

rule cmarrt_call_peaks:
    input:
        lambda wildcards: determine_cmarrt_input(wildcards.sample, wildcards.model, config, pep)
    output:
        "results/peak_calling/{model}/cmarrt/{sample}.narrowPeak"
    log:
        stdout="results/peak_calling/logs/{model}/cmarrt/{sample}_cmarrt.log",
        stderr="results/peak_calling/logs/{model}/cmarrt/{sample}_cmarrt.err"
    params:
        cmarrt_param_string = lambda wildcards: lookup_in_config_persample(config,\
        pep, ["peak_calling", wildcards.model, "cmarrt_param_string"], "--resolution 25 --plots"),
        window_size = lambda wildcards: lookup_in_config_persample(config,\
        pep, ["peak_calling", wildcards.model, "cmarrt_window_size"], 25),
        outpre = lambda wildcards: "results/peak_calling/%s/cmarrt/%s"%(wildcards.model, wildcards.sample),
        resolution = RES,
    conda:
        "../envs/peak_calling.yaml"
    shell:
        "python3 "
        "workflow/CMARRT_python/run_cmarrt_bigwig.py "
        " {input} {params.window_size} "
        "-o {params.outpre} "
        "--resolution {params.resolution} "
        "{params.cmarrt_param_string} > {log.stdout} 2> {log.stderr}"


def get_macs2_matching_input(sample, pep):
   input_sample = lookup_sample_metadata(sample, "input_sample", pep)
   return "results/alignment/bowtie2/%s_sorted.bam"%(input_sample)

rule macs2_call_peaks:
    input:
        ext = "results/alignment/bowtie2/{sample}_sorted.bam",
        inp = lambda wildcards: get_macs2_matching_input(wildcards.sample, pep),
        genome_size= lambda wildcards: determine_effective_genome_size_file(wildcards.sample, config, pep)
    output:
        "results/peak_calling/{model}/macs2/{sample}_peaks.xls"
    log:
        stdout="results/peak_calling/logs/{model}/macs2/{sample}_macs2.log",
        stderr="results/peak_calling/logs/{model}/macs2/{sample}_macs2.err"
    params:
        macs2_param_string = lambda wildcards: lookup_in_config_persample(config,\
        pep, ["peak_calling", wildcards.model, "macs2_param_string"], wildcards.sample,\
        "--broad") 
    conda:
        "../envs/peak_calling.yaml"
    shell:
        "macs2 callpeak -t {input.ext} -c {input.inp} -n {wildcards.sample} "
        "--outdir results/peak_calling/{wildcards.model}/macs2/ "
        "-f BAMPE  {params.macs2_param_string} "
        "-g $(cat {input.genome_size}) > {log.stdout} 2> {log.stderr}"

