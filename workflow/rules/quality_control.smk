## HELPER FUNCTIONS inherited from parent SnakeFile:
# samples(pep)
# lookup_sample_metadata(sample, key, pep)

# Rule to remove everything
rule clean_quality_control:
    shell:
        "rm -fr results/quality_control/"

# Rule to create everything
rule run_quality_control:
    input:
        "results/quality_control/read_qc.done",
        "results/quality_control/ChIP_qc.done"
    output:
        "results/quality_control/multiqc_report.html"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "multiqc results/ -o results/quality_control/ --config workflow/envs/multiqc_config.yaml"



# General read QC
def fastqc_files_output(pep, type_string = "processed"):
    out = []
    for sample in samples(pep):
        if determine_single_end(sample, pep):
            out.append("results/quality_control/fastqc_%s/%s_%s_R0_fastqc.html"%(type_string, sample, type_string))
        else:
            out.append("results/quality_control/fastqc_%s/%s_%s_R1_fastqc.html"%(type_string, sample, type_string))
            out.append("results/quality_control/fastqc_%s/%s_%s_R2_fastqc.html"%(type_string,sample, type_string))
    return out

rule read_qc:
    input:
        fastqc_files_output(pep, "processed"),
        fastqc_files_output(pep, "raw")
    output:
        touch("results/quality_control/read_qc.done")



rule fastqc_raw:
    message: "Running fastqc on raw reads for {wildcards.sample}"
    input:
       lambda wildcards: match_fastq_to_sample(wildcards.sample, wildcards.pair, pep) 
    output:
        "results/quality_control/fastqc_raw/{sample}_raw_{pair}_fastqc.html"
    threads: 1
    resources:
        mem_mb=5000
    log:
        stdout="results/quality_control/logs/fastqc_raw/{sample}_{pair}_raw.log",
        stderr="results/quality_control/logs/fastqc_raw/{sample}_{pair}_raw.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "zcat {input:q} | fastqc stdin:{wildcards.sample}_raw_{wildcards.pair} "
        "-o results/quality_control/fastqc_raw > {log.stdout} 2> {log.stderr}"

def fastqc_processed_input(sample, pair, pep):
    se = determine_single_end(sample, pep)
    if se and pair == "R0":
        out = "results/preprocessing/trimmomatic/%s_trim_R0.fastq.gz"%(sample)
    elif se:
        raise ValueError("Single end reads do not have an R1 or R2 file")
    else:
        out = "results/preprocessing/trimmomatic/%s_trim_paired_%s.fastq.gz"%(sample, pair)
    return out

rule fastqc_processed:
    message: "Running fastqc on processed reads for {wildcards.sample} {wildcards.pair}"
    input:
        lambda wildcards: fastqc_processed_input(wildcards.sample, wildcards.pair, pep)
    output:
        "results/quality_control/fastqc_processed/{sample}_processed_{pair}_fastqc.html"
    threads: 1
    resources:
        mem_mb=5000
    conda:
        "../envs/quality_control.yaml"
    log:
        stdout="results/quality_control/logs/fastqc_processed/{sample}_processed_{pair}.log",
        stderr="results/quality_control/logs/fastqc_processed/{sample}_processed_{pair}.err"
    shell:
        "zcat {input:q} | fastqc stdin:{wildcards.sample}_processed_{wildcards.pair} "
        "-o results/quality_control/fastqc_processed > {log.stdout} 2> {log.stderr}"

# ChIP QC will be done by groups thus we need to write a few helpers

def determine_grouping_category(config):
    if "quality_control" in config and "group_by" in config["quality_control"]:
        grouping_category = config["quality_control"]["group_by"]
    else:
        grouping_category = "genome"
    return grouping_category

def get_sample_by_group(group, pep):
    samp_table = pep.sample_table
    grouping_category = determine_grouping_category(config)
    samples = samp_table.loc[samp_table[grouping_category] == group, "sample_name"]
    return samples.tolist()

def qc_groups(config, pep):
    column = determine_grouping_category(config)
    return pep.sample_table[column].unique().tolist()

# OVERALL RULE FOR ChIP QC

rule ChIP_QC:
    input:
        expand("results/quality_control/deeptools_QC/fingerprint/{group}_fingerprint.png", group = qc_groups(config, pep)),
        #expand("deeptools_QC/{samps}_GCBias_freqs.txt", samps=samples(pep)),
        expand("results/quality_control/deeptools_QC/corHeatmap/{group}_corHeatmap.png", group = qc_groups(config, pep)),
        expand("results/quality_control/deeptools_QC/corScatter/{group}_corScatterplot.png", group = qc_groups(config, pep)),
        expand("results/quality_control/deeptools_QC/fragment_sizes/{group}_bamPEFragmentSize.png", group = qc_groups(config, pep)),
        expand("results/quality_control/deeptools_QC/plotCoverage_rmdups/{group}_plotCoverage_rmdups.png", group = qc_groups(config, pep)),
        expand("results/quality_control/deeptools_QC/plotCoverage/{group}_plotCoverage.png", group = qc_groups(config, pep)),
        expand("results/quality_control/deeptools_QC/PCA/{group}_plotPCA.png", group = qc_groups(config, pep))
    output:
        touch("results/quality_control/ChIP_qc.done")


rule deeptools_QC_fingerprint:
    input:
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)],
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam.bai"%samp for samp in get_sample_by_group(wildcards.group, pep)]
    output:
        outplot="results/quality_control/deeptools_QC/fingerprint/{group}_fingerprint.png",
        rawcounts="results/quality_control/deeptools_QC/fingerprint/{group}_fingerprint_counts.txt",
        qualmetrics="results/quality_control/deeptools_QC/fingerprint/{group}_fingerprint_qual_metrics.txt"
    params:
        labels = lambda wildcards: " ".join([samp for samp in get_sample_by_group(wildcards.group, pep)]),
        bams = lambda wildcards: " ".join(["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)])
    conda:
        "../envs/quality_control.yaml"
    threads:
        10
    log:
        stdout="results/quality_control/logs/deeptools_QC/fingerprint/{group}_fingerprint.log",
        stderr="results/quality_control/logs/deeptools_QC/fingerprint/{group}_fingerprint.err"

    shell:
        "plotFingerprint -b {params.bams} --plotFile {output.outplot} "
        "--outRawCounts {output.rawcounts} --outQualityMetrics {output.qualmetrics} "
        "--labels {params.labels} "
        "--binSize 500 "
        "--numberOfSamples 9200 --numberOfProcessors {threads} --extendReads "
        "--minMappingQuality 10 "
        "--samFlagInclude 66 > {log.stdout} 2> {log.stderr}"

rule deeptools_QC_multiBamSummary:
    input: 
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)],
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam.bai"%samp for samp in get_sample_by_group(wildcards.group, pep)]
    output:
        "results/quality_control/deeptools_QC/{group}_coverage_matrix.npz"
    params:
        labels = lambda wildcards: " ".join([samp for samp in get_sample_by_group(wildcards.group, pep)]),
        bams = lambda wildcards: " ".join(["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)])
    threads:
        10
    log:
        stdout="results/quality_control/logs/deeptools_QC/{group}_multiBAMSummary.log",
        stderr="results/quality_control/logs/deeptools_QC/{group}_multiBAMSummary.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "multiBamSummary bins -b {params.bams} -o {output} "
        "--labels {params.labels} "
        "--binSize 1000 "
        "--numberOfProcessors {threads} --extendReads "
        "--minMappingQuality 10 "
        "--samFlagInclude 66 > {log.stdout} 2> {log.stderr}"

rule deeptools_QC_corHeatmap:
    input:
        "results/quality_control/deeptools_QC/{group}_coverage_matrix.npz"
    output:
        plot="results/quality_control/deeptools_QC/corHeatmap/{group}_corHeatmap.png",
        cormat="results/quality_control/deeptools_QC/corHeatmap/{group}_corvalues.txt"
    log:
        stdout="results/quality_control/logs/deeptools_QC/corHeatmap/{group}_corHeatmap.log",
        stderr="results/quality_control/logs/deeptools_QC/corHetamap/{group}_corHeatmap.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "plotCorrelation --corData {input} --corMethod 'spearman' "
        "--whatToPlot 'heatmap' --plotFile {output.plot} "
        "--colorMap 'viridis' "
        "--outFileCorMatrix {output.cormat} > {log.stdout} 2> {log.stderr}"

rule deeptools_QC_plotPCA:
    input:
        "results/quality_control/deeptools_QC/{group}_coverage_matrix.npz"
    output:
        plot="results/quality_control/deeptools_QC/PCA/{group}_plotPCA.png",
        pcaout="results/quality_control/deeptools_QC/PCA/{group}_PCA_data.txt"
    log:
        stdout="results/quality_control/logs/deeptools_QC/PCA/{group}_plotPCA.log",
        stderr="results/quality_control/logs/deeptools_QC/PCA/{group}_plotPCA.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "plotPCA --corData {input} "
        "--plotFile {output.plot} "
        "--outFileNameData {output.pcaout} > {log.stdout} 2> {log.stderr}"

rule deeptools_QC_corScatterplot:
    input:
        "results/quality_control/deeptools_QC/{group}_coverage_matrix.npz"
    output:
        plot="results/quality_control/deeptools_QC/corScatter/{group}_corScatterplot.png"
    log:
        stdout="results/quality_control/logs/deeptools_QC/corScatter/{group}_corScatterplot.log",
        stderr="results/quality_control/logs/deeptools_QC/corScatter/{group}_corScatterplot.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "plotCorrelation --corData {input} --corMethod 'spearman' "
        "--whatToPlot 'scatterplot' --plotFile {output.plot} "
        "> {log.stdout} 2> {log.stderr}"

rule deeptools_QC_plotCoverage:
    input: 
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)],
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam.bai"%samp for samp in get_sample_by_group(wildcards.group, pep)]
    output:
        plot="results/quality_control/deeptools_QC/plotCoverage/{group}_plotCoverage.png",
        counts="results/quality_control/deeptools_QC/plotCoverage/{group}_plotCoverage_count.txt"
    params:
        labels = lambda wildcards: " ".join([samp for samp in get_sample_by_group(wildcards.group, pep)]),
        bams = lambda wildcards: " ".join(["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)])
    threads:
        10
    log:
        stdout="results/quality_control/logs/deeptools_QC/plotCoverage/{group}_plotCoverage.log",
        stderr="results/quality_control/logs/deeptools_QC/plotCoverage/{group}_plotCoverage.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "plotCoverage -b {params.bams} -o {output.plot} "
        "--labels {params.labels} "
        "--numberOfProcessors {threads} --extendReads "
        "--numberOfSamples 1000 "
        "--outRawCounts {output.counts} "
        "--minMappingQuality 10 "
        "--samFlagInclude 66 > {log.stdout} 2> {log.stderr}"

rule deeptools_QC_plotCoverage_rmdups:
    input: 
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)],
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam.bai"%samp for samp in get_sample_by_group(wildcards.group, pep)]
    output:
        plot="results/quality_control/deeptools_QC/plotCoverage_rmdups/{group}_plotCoverage_rmdups.png",
        counts="results/quality_control/deeptools_QC/plotCoverage_rmdups/{group}_plotCoverage_count_rmdups.txt"
    params:
        labels = lambda wildcards: " ".join([samp for samp in get_sample_by_group(wildcards.group, pep)]),
        bams = lambda wildcards: " ".join(["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)])
    threads:
        10
    log:
        stdout="results/quality_control/logs/deeptools_QC/plotCoverage_rmdups/{group}_plotCoverage_rmdups.log",
        stderr="results/quality_control/logs/deeptools_QC/plotCoverage_rmdups/{group}_plotCoverage_rmdups.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "plotCoverage -b {params.bams} --plotFile {output.plot} "
        "--labels {params.labels} "
        "--numberOfProcessors {threads} --extendReads --ignoreDuplicates "
        "--numberOfSamples 1000 "
        "--outRawCounts {output.counts} "
        "--minMappingQuality 10 "
        "--samFlagInclude 66 > {log.stdout} 2> {log.stderr}"

rule deeptools_QC_bamPEFragmentSize:
    input:
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)],
        lambda wildcards: ["results/alignment/bowtie2/%s_sorted.bam.bai"%samp for samp in get_sample_by_group(wildcards.group, pep)]
    output:
        plot="results/quality_control/deeptools_QC/fragment_sizes/{group}_bamPEFragmentSize.png",
        fragment_hist="results/quality_control/deeptools_QC/fragment_sizes/{group}_bamPEFragmentSize.txt",
        table="results/quality_control/deeptools_QC/fragment_sizes/{group}_bamPEFragmentSize_table.txt"
    params:
        labels = lambda wildcards: " ".join([samp for samp in get_sample_by_group(wildcards.group, pep)]),
        bams = lambda wildcards: " ".join(["results/alignment/bowtie2/%s_sorted.bam"%samp for samp in get_sample_by_group(wildcards.group, pep)])
    threads:
        10
    log:
        stdout="results/quality_control/logs/deeptools_QC/fragment_sizes/{group}_bamPEFragmentSize.log",
        stderr="results/quality_control/logs/deeptools_QC/fragment_sizes/{group}_bamPEFragmentSize.err"
    conda:
        "../envs/quality_control.yaml"
    shell:
        "bamPEFragmentSize -b {params.bams} --histogram {output.plot} "
        "--samplesLabel {params.labels} "
        "--numberOfProcessors {threads} "
        "--distanceBetweenBins 10000 "
        "--table {output.table} --outRawFragmentLengths {output.fragment_hist}  > {log.stdout} 2> {log.stderr}"

# WORK IN PROGRESS
rule deeptools_QC_computeGCBias:
    input: 
        "results/bowtie2/{sample}_sorted.bam"
    output:
        gcfile="results/quality_control/deeptools_QC/GCbias/{sample}_GCBias_freqs.txt",
        gcplot="results/quality_control/deeptools_QC/GCbias/{sample}_GCBias_plot.png"
    threads:
        5
    log:
        stdout="results/quality_control/logs/deeptools_QC/{sample}_GCBias.log",
        stderr="results/quality_control/logs/deeptools_QC/{sample}_GCBias.err"
    params:
        genome_size = lambda wildcards: determine_genome_size(sample, config, pep)
    conda:
        "../envs/quality_control.yaml"
    shell:
        "computeGCBias -b {input} --effectiveGenomeSize {params.genome_size} "
        "-g /mnt/scratch/mbwolfe/genomes/U00096_3.2bit "
        "--sampleSize 50000 "
        "--numberOfProcessors {threads} "
        "--GCbiasFrequenciesFile {output.gcfile}  > {log.stdout} 2> {log.stderr}"


