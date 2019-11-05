/*
* Copyright (c) 2019, NVIDIA CORPORATION.  All rights reserved.
*
* NVIDIA CORPORATION and its licensors retain all intellectual property
* and proprietary rights in and to this software, related documentation
* and any modifications thereto.  Any use, reproduction, disclosure or
* distribution of this software and related documentation without an express
* license agreement from NVIDIA CORPORATION is strictly prohibited.
*/

#include "gtest/gtest.h"

#include <thrust/device_vector.h>
#include <thrust/host_vector.h>

#include "cudamapper_file_location.hpp"
#include "../src/index_gpu_two_indices.cuh"
#include "../src/minimizer.hpp"

namespace claragenomics
{
namespace cudamapper
{

void test_function(const std::string& filename,
                   const read_id_t first_read_id,
                   const read_id_t past_the_last_read_id,
                   const std::uint64_t kmer_size,
                   const std::uint64_t window_size,
                   const thrust::host_vector<representation_t>& expected_representations,
                   const thrust::host_vector<position_in_read_t>& expected_positions_in_reads,
                   const thrust::host_vector<read_id_t>& expected_read_ids,
                   const thrust::host_vector<SketchElement::DirectionOfRepresentation>& expected_directions_of_reads,
                   const std::vector<std::string>& expected_read_id_to_read_name,
                   const std::vector<std::uint32_t>& expected_read_id_to_read_length,
                   const std::uint64_t expected_number_of_reads)
{
    std::unique_ptr<io::FastaParser> parser = io::create_fasta_parser(filename);
    IndexGPUTwoIndices<Minimizer> index(parser.get(),
                                        first_read_id,
                                        past_the_last_read_id,
                                        kmer_size,
                                        window_size);

    ASSERT_EQ(index.number_of_reads(), expected_number_of_reads);
    if (0 == expected_number_of_reads)
    {
        return;
    }

    ASSERT_EQ(expected_number_of_reads, expected_read_id_to_read_name.size());
    ASSERT_EQ(expected_number_of_reads, expected_read_id_to_read_length.size());
    for (read_id_t read_id = first_read_id; read_id < past_the_last_read_id; ++read_id)
    {
        ASSERT_EQ(index.read_id_to_read_length(read_id), expected_read_id_to_read_length[read_id - first_read_id]) << "read_id: " << read_id;
        ASSERT_EQ(index.read_id_to_read_name(read_id), expected_read_id_to_read_name[read_id - first_read_id]) << "read_id: " << read_id;
    }

    // check arrays
    const thrust::device_vector<representation_t>& representations_d                             = index.representations();
    const thrust::device_vector<position_in_read_t>& positions_in_reads_d                        = index.positions_in_reads();
    const thrust::device_vector<read_id_t>& read_ids_d                                           = index.read_ids();
    const thrust::device_vector<SketchElement::DirectionOfRepresentation>& directions_of_reads_d = index.directions_of_reads();
    const thrust::host_vector<representation_t>& representations_h(representations_d);
    const thrust::host_vector<position_in_read_t>& positions_in_reads_h(positions_in_reads_d);
    const thrust::host_vector<read_id_t>& read_ids_h(read_ids_d);
    const thrust::host_vector<SketchElement::DirectionOfRepresentation>& directions_of_reads_h(directions_of_reads_d);
    ASSERT_EQ(representations_h.size(), expected_representations.size());
    ASSERT_EQ(positions_in_reads_h.size(), expected_positions_in_reads.size());
    ASSERT_EQ(read_ids_h.size(), expected_read_ids.size());
    ASSERT_EQ(directions_of_reads_h.size(), expected_directions_of_reads.size());
    ASSERT_EQ(representations_h.size(), positions_in_reads_h.size());
    ASSERT_EQ(positions_in_reads_h.size(), read_ids_h.size());
    ASSERT_EQ(read_ids_h.size(), directions_of_reads_h.size());
    for (std::size_t i = 0; i < expected_positions_in_reads.size(); ++i)
    {
        EXPECT_EQ(representations_h[i], expected_representations[i]) << "i: " << i;
        EXPECT_EQ(positions_in_reads_h[i], expected_positions_in_reads[i]) << "i: " << i;
        EXPECT_EQ(read_ids_h[i], expected_read_ids[i]) << "i: " << i;
        EXPECT_EQ(directions_of_reads_h[i], expected_directions_of_reads[i]) << "i: " << i;
    }
}

TEST(TestCudamapperIndexGPUTwoIndices, GATT_4_1)
{
    // >read_0
    // GATT

    // GATT = 0b10001111
    // AATC = 0b00001101 <- minimizer

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/gatt.fasta";
    const std::uint64_t minimizer_size = 4;
    const std::uint64_t window_size    = 1;

    std::vector<std::string> expected_read_id_to_read_name;
    expected_read_id_to_read_name.push_back("read_0");

    std::vector<std::uint32_t> expected_read_id_to_read_length;
    expected_read_id_to_read_length.push_back(4);

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;
    expected_representations.push_back(0b1101);
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::REVERSE);

    test_function(filename,
                  0,
                  1,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  1);
}

TEST(TestCudamapperIndexGPUTwoIndices, GATT_2_3)
{
    // >read_0
    // GATT

    // kmer representation: forward, reverse
    // GA: <20> 31
    // AT: <03> 03
    // TT:  33 <00>

    // front end minimizers: representation, position_in_read, direction, read_id
    // GA : 20 0 F 0
    // GAT: 03 1 F 0

    // central minimizers
    // GATT: 00 2 R 0

    // back end minimizers
    // ATT: 00 2 R 0
    // TT : 00 2 R 0

    // All minimizers: GA(0f), AT(1f), AA(2r)

    // (2r1) means position 2, reverse direction, read 1
    // (1,2) means array block start at element 1 and has 2 elements

    //              0        1        2
    // data arrays: GA(0f0), AT(1f0), AA(2r0)

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/gatt.fasta";
    const std::uint64_t minimizer_size = 2;
    const std::uint64_t window_size    = 3;

    std::vector<std::string> expected_read_id_to_read_name;
    expected_read_id_to_read_name.push_back("read_0");

    std::vector<std::uint32_t> expected_read_id_to_read_length;
    expected_read_id_to_read_length.push_back(4);

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;

    expected_representations.push_back(0b0000); // AA(2r0)
    expected_positions_in_reads.push_back(2);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::REVERSE);
    expected_representations.push_back(0b0011); // AT(1f0)
    expected_positions_in_reads.push_back(1);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b1000); // GA(0f0)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);

    test_function(filename,
                  0,
                  1,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  1);
}

TEST(TestCudamapperIndexGPUTwoIndices, CCCATACC_2_8)
{
    // *** Read is shorter than one full window, the result should be empty ***

    // >read_0
    // CCCATACC

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/cccatacc.fasta";
    const std::uint64_t minimizer_size = 2;
    const std::uint64_t window_size    = 8;

    // all data arrays should be empty

    std::vector<std::string> expected_read_id_to_read_name;

    std::vector<std::uint32_t> expected_read_id_to_read_length;

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;

    test_function(filename,
                  0,
                  1,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  0);
}

// TODO: Cover this case as well
/*TEST(TestCudamapperIndexGPUTwoIndices, CATCAAG_AAGCTA_3_5)
{
    // *** One Read is shorter than one full window, the other is not ***

    // >read_0
    // CATCAAG
    // >read_1
    // AAGCTA

    // ** CATCAAG **

    // kmer representation: forward, reverse
    // CAT:  103 <032>
    // ATC: <031> 203
    // TCA: <310> 320
    // CAA: <100> 332
    // AAG: <002> 133

    // front end minimizers: representation, position_in_read, direction, read_id
    // CAT   : 032 0 R 0
    // CATC  : 031 1 F 0
    // CATCA : 031 1 F 0
    // CATCAA: 031 1 F 0

    // central minimizers
    // CATCAAG: 002 4 F 0

    // back end minimizers
    // ATCAAG: 002 4 F 0
    // TCAAG : 002 4 F 0
    // CAAG  : 002 4 F 0
    // AAG   : 002 4 F 0

    // ** AAGCTA **
    // ** read does not fit one array **

    // All minimizers: ATG(0r0), ATC(1f0), AAG(4f0)

    // (2r1) means position 2, reverse direction, read 1
    // (1,2) means array block start at element 1 and has 2 elements

    //              0         1         2
    // data arrays: AAG(4f0), ATC(1f0), ATG(0r0)

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/catcaag_aagcta.fasta";
    const std::uint64_t minimizer_size = 3;
    const std::uint64_t window_size    = 5;

    std::vector<std::string> expected_read_id_to_read_name;
    expected_read_id_to_read_name.push_back("read_0");

    std::vector<std::uint32_t> expected_read_id_to_read_length;
    expected_read_id_to_read_length.push_back(7);

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;
    expected_representations.push_back(0b000010); // AAG(4f0)
    expected_positions_in_reads.push_back(4);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b001101); // ATC(1f0)
    expected_positions_in_reads.push_back(1);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b001110); // ATG(0r0)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::REVERSE);

    test_function(filename,
                  0,
                  2,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  1); // <- only one read goes into index, the other is too short
}*/

TEST(TestCudamapperIndexGPUTwoIndices, CCCATACC_3_5)
{
    // >read_0
    // CCCATACC

    // ** CCCATAC **

    // kmer representation: forward, reverse
    // CCC: <111> 222
    // CCA: <110> 322
    // CAT:  103 <032>
    // ATA: <030> 303
    // TAC:  301 <230>
    // ACC: <011> 223

    // front end minimizers: representation, position_in_read, direction
    // CCC   : 111 0 F
    // CCCA  : 110 1 F
    // CCCAT : 032 2 R
    // CCCATA: 030 3 F

    // central minimizers
    // CCCATAC: 030 3 F
    // CCATACC: 011 5 F

    // back end minimizers
    // CATACC: 011 5 F
    // ATACC : 011 5 F
    // TACC  : 011 5 F
    // ACC   : 011 5 F

    // All minimizers: CCC(0f), CCA(1f), ATG(2r), ATA(3f), ACC(5f)

    // (2r1) means position 2, reverse direction, read 1
    // (1,2) means array block start at element 1 and has 2 elements

    //              0         1         2
    // data arrays: ACC(5f0), ATA(3f0), ATG(2r0), CCA(1f0), CCC(0f0)

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/cccatacc.fasta";
    const std::uint64_t minimizer_size = 3;
    const std::uint64_t window_size    = 5;

    std::vector<std::string> expected_read_id_to_read_name;
    expected_read_id_to_read_name.push_back("read_0");

    std::vector<std::uint32_t> expected_read_id_to_read_length;
    expected_read_id_to_read_length.push_back(8);

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;
    expected_representations.push_back(0b000101); // ACC(5f0)
    expected_positions_in_reads.push_back(5);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b001100); // ATA(3f0)
    expected_positions_in_reads.push_back(3);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b001110); // ATG(2r0)
    expected_positions_in_reads.push_back(2);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::REVERSE);
    expected_representations.push_back(0b010100); // CCA(1f0)
    expected_positions_in_reads.push_back(1);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b010101); // CCC(0f0)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);

    test_function(filename,
                  0,
                  1,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  1);
}

TEST(TestCudamapperIndexGPUTwoIndices, CATCAAG_AAGCTA_3_2)
{
    // >read_0
    // CATCAAG
    // >read_1
    // AAGCTA

    // ** CATCAAG **

    // kmer representation: forward, reverse
    // CAT:  103 <032>
    // ATC: <031> 203
    // TCA: <310> 320
    // CAA: <100> 332
    // AAG: <002> 133

    // front end minimizers: representation, position_in_read, direction, read_id
    // CAT: 032 0 R 0

    // central minimizers
    // CATC: 031 1 F 0
    // ATCA: 031 1 F 0
    // TCAA: 100 3 F 0
    // CAAG: 002 4 F 0

    // back end minimizers
    // AAG: 002 4 F 0

    // All minimizers: ATC(1f), CAA(3f), AAG(4f), ATG(0r)

    // ** AAGCTA **

    // kmer representation: forward, reverse
    // AAG: <002> 133
    // AGC: <021> 213
    // GCT:  213 <021>
    // CTA: <130> 302

    // front end minimizers: representation, position_in_read, direction, read_id
    // AAG: 002 0 F 1

    // central minimizers
    // AAGC: 002 0 F 1
    // AGCT: 021 2 R 1 // only the last minimizer is saved
    // GCTA: 021 2 R 1

    // back end minimizers
    // CTA: 130 3 F 1

    // All minimizers: AAG(0f), AGC(1f), CTA(3f)

    // (2r1) means position 2, reverse direction, read 1
    // (1,2) means array block start at element 1 and has 2 elements

    //              0         1         2         3         4         5         6
    // data arrays: AAG(4f0), AAG(0f1), AGC(2r1), ATC(1f0), ATG(0r0), CAA(3f0), CTA(3f1)

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/catcaag_aagcta.fasta";
    const std::uint64_t minimizer_size = 3;
    const std::uint64_t window_size    = 2;

    std::vector<std::string> expected_read_id_to_read_name;
    expected_read_id_to_read_name.push_back("read_0");
    expected_read_id_to_read_name.push_back("read_1");

    std::vector<std::uint32_t> expected_read_id_to_read_length;
    expected_read_id_to_read_length.push_back(7);
    expected_read_id_to_read_length.push_back(6);

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;

    expected_representations.push_back(0b000010); // AAG(4f0)
    expected_positions_in_reads.push_back(4);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b000010); // AAG(0f1)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b001001); // AGC(2r1)
    expected_positions_in_reads.push_back(2);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::REVERSE);
    expected_representations.push_back(0b001101); // ATC(1f0)
    expected_positions_in_reads.push_back(1);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b001110); // ATG(0r0)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::REVERSE);
    expected_representations.push_back(0b010000); // CAA(3f0)
    expected_positions_in_reads.push_back(3);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b011100); // CTA(3f1)
    expected_positions_in_reads.push_back(3);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);

    test_function(filename,
                  0,
                  2,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  2);
}

TEST(TestCudamapperIndexGPUTwoIndices, AAAACTGAA_GCCAAAG_2_3)
{
    // >read_0
    // AAAACTGAA
    // >read_1
    // GCCAAAG

    // ** AAAACTGAA **

    // kmer representation: forward, reverse
    // AA: <00> 33
    // AA: <00> 33
    // AA: <00> 33
    // AC: <01> 23
    // CT:  13 <02>
    // TG:  32 <10>
    // GA: <20> 31
    // AA: <00> 33

    // front end minimizers: representation, position_in_read, direction, read_id
    // AA : 00 0 F 0
    // AAA: 00 1 F 0

    // central minimizers
    // AAAA: 00 2 F 0
    // AAAC: 00 2 F 0
    // AACT: 00 2 F 0
    // ACTG: 01 3 F 0
    // CTGA: 02 4 R 0
    // TGAA: 00 7 F 0

    // back end minimizers
    // GAA: 00 7 F 0
    // AA : 00 7 F 0

    // All minimizers: AA(0f), AA(1f), AA(2f), AC(3f), AG(4r), AA (7f)

    // ** GCCAAAG **

    // kmer representation: forward, reverse
    // GC: <21> 21
    // CC: <11> 22
    // CA: <10> 32
    // AA: <00> 33
    // AA: <00> 33
    // AG: <03> 21

    // front end minimizers: representation, position_in_read, direction, read_id
    // GC : 21 0 F 0
    // GCC: 11 1 F 0

    // central minimizers
    // GCCA: 10 2 F 0
    // CCAA: 00 3 F 0
    // CAAA: 00 4 F 0
    // AAAG: 00 4 F 0

    // back end minimizers
    // AAG: 00 4 F 0
    // AG : 03 5 F 0

    // All minimizers: GC(0f), CC(1f), CA(2f), AA(3f), AA(4f), AG(5f)

    // (2r1) means position 2, reverse direction, read 1
    // (1,2) means array block start at element 1 and has 2 elements

    //              0        1        2        3        4        5        6        7        8        9        10       11
    // data arrays: AA(0f0), AA(1f0), AA(2f0), AA(7f0), AA(3f1), AA(4f1), AC(3f0), AG(4r0), AG(5f1), CA(2f1), CC(1f1), GC(0f1)

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/aaaactgaa_gccaaag.fasta";
    const std::uint64_t minimizer_size = 2;
    const std::uint64_t window_size    = 3;

    std::vector<std::string> expected_read_id_to_read_name;
    expected_read_id_to_read_name.push_back("read_0");
    expected_read_id_to_read_name.push_back("read_1");

    std::vector<std::uint32_t> expected_read_id_to_read_length;
    expected_read_id_to_read_length.push_back(9);
    expected_read_id_to_read_length.push_back(7);

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;
    expected_representations.push_back(0b0000); // AA(0f0)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0000); // AA(1f0)
    expected_positions_in_reads.push_back(1);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0000); // AA(2f0)
    expected_positions_in_reads.push_back(2);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0000); // AA(7f0)
    expected_positions_in_reads.push_back(7);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0000); // AA(3f1)
    expected_positions_in_reads.push_back(3);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0000); // AA(4f1)
    expected_positions_in_reads.push_back(4);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0001); // AC(3f0)
    expected_positions_in_reads.push_back(3);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0010); // AG(4r0)
    expected_positions_in_reads.push_back(4);
    expected_read_ids.push_back(0);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::REVERSE);
    expected_representations.push_back(0b0010); // AG(5f1)
    expected_positions_in_reads.push_back(5);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0100); // CA(2f1)
    expected_positions_in_reads.push_back(2);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0101); // CC(1f1)
    expected_positions_in_reads.push_back(1);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b1001); // GC(0f1)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);

    test_function(filename,
                  0,
                  2,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  2);
}

TEST(TestCudamapperIndexGPUTwoIndices, AAAACTGAA_GCCAAAG_2_3_only_second_read_in_index)
{
    // >read_0
    // AAAACTGAA
    // >read_1
    // GCCAAAG

    // ** AAAACTGAA **
    // only second read goes into index

    // ** GCCAAAG **

    // kmer representation: forward, reverse
    // GC: <21> 21
    // CC: <11> 22
    // CA: <10> 32
    // AA: <00> 33
    // AA: <00> 33
    // AG: <03> 21

    // front end minimizers: representation, position_in_read, direction, read_id
    // GC : 21 0 F 0
    // GCC: 11 1 F 0

    // central minimizers
    // GCCA: 10 2 F 0
    // CCAA: 00 3 F 0
    // CAAA: 00 4 F 0
    // AAAG: 00 4 F 0

    // back end minimizers
    // AAG: 00 4 F 0
    // AG : 03 5 F 0

    // All minimizers: GC(0f), CC(1f), CA(2f), AA(3f), AA(4f), AG(5f)

    // (2r1) means position 2, reverse direction, read 1
    // (1,2) means array block start at element 1 and has 2 elements

    //              0        1        2        3        4        5
    // data arrays: AA(3f1), AA(4f1), AG(5f1), CA(2f1), CC(1f1), GC(0f1)

    const std::string filename         = std::string(CUDAMAPPER_BENCHMARK_DATA_DIR) + "/aaaactgaa_gccaaag.fasta";
    const std::uint64_t minimizer_size = 2;
    const std::uint64_t window_size    = 3;

    // only take second read
    std::vector<std::string> expected_read_id_to_read_name;
    expected_read_id_to_read_name.push_back("read_1");

    std::vector<std::uint32_t> expected_read_id_to_read_length;
    expected_read_id_to_read_length.push_back(7);

    std::vector<representation_t> expected_representations;
    std::vector<position_in_read_t> expected_positions_in_reads;
    std::vector<read_id_t> expected_read_ids;
    std::vector<SketchElement::DirectionOfRepresentation> expected_directions_of_reads;
    expected_representations.push_back(0b0000); // AA(3f1)
    expected_positions_in_reads.push_back(3);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0000); // AA(4f1)
    expected_positions_in_reads.push_back(4);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0010); // AG(5f1)
    expected_positions_in_reads.push_back(5);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0100); // CA(2f1)
    expected_positions_in_reads.push_back(2);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b0101); // CC(1f1)
    expected_positions_in_reads.push_back(1);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);
    expected_representations.push_back(0b1001); // GC(0f1)
    expected_positions_in_reads.push_back(0);
    expected_read_ids.push_back(1);
    expected_directions_of_reads.push_back(SketchElement::DirectionOfRepresentation::FORWARD);

    test_function(filename,
                  1, // <- only take second read
                  2,
                  minimizer_size,
                  window_size,
                  expected_representations,
                  expected_positions_in_reads,
                  expected_read_ids,
                  expected_directions_of_reads,
                  expected_read_id_to_read_name,
                  expected_read_id_to_read_length,
                  1);
}

} // namespace cudamapper
} // namespace claragenomics