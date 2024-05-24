/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

include { FASTQC                 } from '../modules/nf-core/fastqc/main'
include { MULTIQC                } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap       } from 'plugin/nf-validation'
include { paramsSummaryMultiqc   } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText } from '../subworkflows/local/utils_nfcore_rnafoldanalyzer_pipeline'

include { CAT_CAT                } from '../modules/nf-core/cat/cat/main'
include { GUNZIP                 } from '../modules/nf-core/gunzip/main'
include { CLUSTALO_ALIGN         } from '../modules/nf-core/clustalo/align/main'
include { GUNZIP as GUNZIP_MSA   } from '../modules/nf-core/gunzip/main'
include { FASTTREE               } from '../modules/nf-core/fasttree/main'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow RNAFOLDANALYZER {

    take:
    ch_samplesheet // channel: samplesheet read in from --input

    main:

    ch_versions = Channel.empty()
    ch_multiqc_files = Channel.empty()

    ch_samplesheet.view()

    // group paths across samples
    ch_grouped_fasta_gz = ch_samplesheet
        .map ( meta, fasta_gz -> [ [ id:'all_samples' ], fasta_gz])
        .groupTuple( sort: 'deep' )

    //
    // MODULE: Concatinate fasta files
    //
    ch_cat_fasta_gz = CAT_CAT ( ch_grouped_fasta_gz ).file_out
    ch_versions = ch_versions.mix( CAT_CAT.out.versions )

    //
    // MODULE: Gunzip FASTA files for input into Clustal Omega
    //
    ch_fasta = GUNZIP ( ch_cat_fasta_gz ).gunzip
    ch_versions = ch_versions.mix ( GUNZIP.out.versions )

    //
    // MODULE: Run Clustal Omega align
    //
    ch_msa_gz = CLUSTALO_ALIGN ( ch_fasta, [[:],[]], true ).alignment
    ch_versions = ch_versions.mix( CLUSTALO_ALIGN.out.versions )

    //
    // MODULE: Gunzip FASTA files for input into FastTree
    //
    ch_msa = GUNZIP_MSA ( ch_msa_gz ).gunzip
    ch_versions = ch_versions.mix ( GUNZIP_MSA.out.versions )

    //
    // MODULE: Run FASTTREE to create Newick phylogeny
    //
    // remove meta from chanel
    ch_msa_nometa = ch_msa.map{ meta, path -> [path] }
    ch_msa_nometa.view()
    FASTTREE ( ch_msa_nometa )
    ch_versions = ch_versions.mix ( FASTTREE.out.versions )

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(storeDir: "${params.outdir}/pipeline_info", name: 'nf_core_pipeline_software_mqc_versions.yml', sort: true, newLine: true)
        .set { ch_collated_versions }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_config                     = Channel.fromPath("$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config              = params.multiqc_config ? Channel.fromPath(params.multiqc_config, checkIfExists: true) : Channel.empty()
    ch_multiqc_logo                       = params.multiqc_logo ? Channel.fromPath(params.multiqc_logo, checkIfExists: true) : Channel.empty()
    summary_params                        = paramsSummaryMap(workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary                   = Channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ? file(params.multiqc_methods_description, checkIfExists: true) : file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = Channel.value(methodsDescriptionText(ch_multiqc_custom_methods_description))
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files                      = ch_multiqc_files.mix(ch_methods_description.collectFile(name: 'methods_description_mqc.yaml', sort: false))

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList()
    )

    emit:
    multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]
}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/


// NOTES
//  nextflow run . -profile test,docker --outdir results
//  gzip /workspace/rnafoldanalyzer/assets/test-datasets/input/*.fasta
