# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.

# Stage 1: validate the input and handle the solved cube.
# Search for unsolved cubes is added in the next stage.
#
# a0: input state
# a1: output buffer
# a2: output capacity
# a3: nonzero when the state differs from the solved cube
# Cube solver: IDA* prefix with exact near-goal lookup and distance-11 layer.
# a0=state, a1=out, a2=cap. Only local helper calls; no recursion/heap/M.
    .text
    .globl rubik_solve_asm
    .type rubik_solve_asm, @function
    .align 2
rubik_solve_asm:
    mv t2, a0
    li t3, 7
    li t1, 7
    li t4, 0
    li a3, 0
.Lrubik_check_perm:
    lbu t0, 0(t2)
    addi t0, t0, -49
    bgeu t0, t1, .Lrubik_invalid
    li t5, 1
    sll t5, t5, t0
    and t6, t4, t5
    bne t6, zero, .Lrubik_invalid
    or t4, t4, t5
    li t6, 7
    sub t6, t6, t3
    xor t6, t0, t6
    or a3, a3, t6
    addi t2, t2, 1
    addi t3, t3, -1
    bne t3, zero, .Lrubik_check_perm
    li t3, 7
    li t1, 3
    li t4, 0
.Lrubik_check_orient:
    lbu t0, 0(t2)
    addi t0, t0, -49
    bgeu t0, t1, .Lrubik_invalid
    or a3, a3, t0
    add t4, t4, t0
    bltu t4, t1, .Lrubik_orient_next
    addi t4, t4, -3
.Lrubik_orient_next:
    addi t2, t2, 1
    addi t3, t3, -1
    bne t3, zero, .Lrubik_check_orient
    lbu t0, 0(t2)
    bne t0, zero, .Lrubik_invalid
    bne t4, zero, .Lrubik_invalid
    beq a2, zero, .Lrubik_zero_cap
    bne a3, zero, .Lrubik_search
    sb zero, 0(a1)
    li a0, 0
    ret
.Lrubik_zero_cap:
    li a0, -2
    ret
.Lrubik_invalid:
    li a0, -1
    ret

# Stack: 192 frame bytes, 48 saved s-register bytes, 12 path bytes, saved ra.
# Frame: p:u16@0, o:u16@2, candidate_p:u16@4, candidate_o:u16@6,
# next_move:u8@8, previous_face:u8@9.
.Lrubik_search:
    addi sp, sp, -256
    sw s0, 192(sp)
    sw s1, 196(sp)
    sw s2, 200(sp)
    sw s3, 204(sp)
    sw s4, 208(sp)
    sw s5, 212(sp)
    sw s6, 216(sp)
    sw s7, 220(sp)
    sw s8, 224(sp)
    sw s9, 228(sp)
    sw s10, 232(sp)
    sw s11, 236(sp)
    sw ra, 252(sp)
    mv s0, a1
    mv s1, a2
    addi s11, sp, 240

# Lehmer rank: p = p * remaining + smaller_to_the_right.
# Multipliers are at most seven, so use additions rather than a helper.
    li s2, 0
    mv t2, a0
    li t3, 7
    addi a6, a0, 7
.Lrubik_rank_perm:
    lbu t0, 0(t2)
    li t1, 0
    addi t4, t2, 1
.Lrubik_count_smaller:
    bgeu t4, a6, .Lrubik_rank_multiply
    lbu t5, 0(t4)
    sltu t5, t5, t0
    add t1, t1, t5
    addi t4, t4, 1
    j .Lrubik_count_smaller
.Lrubik_rank_multiply:
    mv t6, s2
    li s2, 0
    mv t4, t3
.Lrubik_rank_add:
    add s2, s2, t6
    addi t4, t4, -1
    bne t4, zero, .Lrubik_rank_add
    add s2, s2, t1
    addi t2, t2, 1
    addi t3, t3, -1
    bne t3, zero, .Lrubik_rank_perm

# The first six orientation digits determine the seventh.
    li s3, 0
    addi t2, a0, 7
    li t3, 6
.Lrubik_rank_orient:
    lbu t0, 0(t2)
    addi t0, t0, -49
    slli t1, s3, 1
    add s3, s3, t1
    add s3, s3, t0
    addi t2, t2, 1
    addi t3, t3, -1
    bne t3, zero, .Lrubik_rank_orient

    la s7, .Lrubik_perm_tables
    la s8, .Lrubik_orient_tables
    la s9, .Lrubik_perm_dist
    la s10, .Lrubik_orient_dist
    add t0, s9, s2
    lbu s5, 0(t0)
    add t0, s10, s3
    lbu t1, 0(t0)
    bgeu s5, t1, .Lrubik_classify
    mv s5, t1

# Membership in the complete distance-11 layer gives an exact lower bound.
# A neighbor not in that layer must have distance 10: adjacent distances
# differ by at most one. Search that neighbor and keep the first move.
.Lrubik_classify:
    li a7, 0
    mv t3, s2
    mv t4, s3
    jal ra, .Lrubik_is11_coords
    beq a0, zero, .Lrubik_new_bound
    li a6, 0
.Lrubik_choose_neighbor:
    li a3, 0
    li a4, 0
    li t2, 3
    bltu a6, t2, .Lrubik_neighbor_face
    li a3, 1
    li a4, 3
    li t2, 6
    bltu a6, t2, .Lrubik_neighbor_face
    li a3, 2
    li a4, 6
.Lrubik_neighbor_face:
    bne a6, a4, .Lrubik_neighbor_turn
    mv t3, s2
    mv t4, s3
.Lrubik_neighbor_turn:
    slli t2, a3, 2
    add t5, s7, t2
    lw t5, 0(t5)
    slli t3, t3, 1
    add t5, t5, t3
    lhu t3, 0(t5)
    add t5, s8, t2
    lw t5, 0(t5)
    slli t4, t4, 1
    add t5, t5, t4
    lhu t4, 0(t5)
    jal ra, .Lrubik_is11_coords
    beq a0, zero, .Lrubik_neighbor_selected
    addi a6, a6, 1
    j .Lrubik_choose_neighbor
.Lrubik_neighbor_selected:
    mv s2, t3
    mv s3, t4
    sb a6, 0(s11)
    li a7, 1
    li s5, 11

# s4=global depth, a7=preserved prefix length, s5=total bound.
.Lrubik_new_bound:
    mv s4, a7
    slli t0, s4, 4
    add s6, sp, t0
    sh s2, 0(s6)
    sh s3, 2(s6)
    sb zero, 8(s6)
    li t0, 3
    beq a7, zero, .Lrubik_root_face_ready
    li t0, 0
    lbu t1, 0(s11)
    li t2, 3
    bltu t1, t2, .Lrubik_root_face_ready
    li t0, 1
    li t2, 6
    bltu t1, t2, .Lrubik_root_face_ready
    li t0, 2
.Lrubik_root_face_ready:
    sb t0, 9(s6)
.Lrubik_search_loop:
    lhu t3, 0(s6)
    lhu t4, 2(s6)
    sub t6, s5, s4
    li t5, 5
    bgeu t5, t6, .Lrubik_terminal
    or t2, t3, t4
    beq t2, zero, .Lrubik_found
    bgeu s4, s5, .Lrubik_backtrack
    lbu t0, 8(s6)
    li t1, 9
    bgeu t0, t1, .Lrubik_backtrack
    addi t1, t0, 1
    sb t1, 8(s6)

# Decode move into face and its first move, without division.
    li a3, 0
    li a4, 0
    li t2, 3
    bltu t0, t2, .Lrubik_face_ready
    li a3, 1
    li a4, 3
    li t2, 6
    bltu t0, t2, .Lrubik_face_ready
    li a3, 2
    li a4, 6
.Lrubik_face_ready:
    lbu t2, 9(s6)
    bne a3, t2, .Lrubik_face_allowed
    addi t2, a4, 3
    sb t2, 8(s6)
    j .Lrubik_search_loop
.Lrubik_face_allowed:
    beq t0, a4, .Lrubik_turn
    lhu t3, 4(s6)
    lhu t4, 6(s6)
.Lrubik_turn:
    slli t2, a3, 2
    add t5, s7, t2
    lw t5, 0(t5)
    slli t3, t3, 1
    add t5, t5, t3
    lhu t3, 0(t5)
    add t5, s8, t2
    lw t5, 0(t5)
    slli t4, t4, 1
    add t5, t5, t4
    lhu t4, 0(t5)
    sh t3, 4(s6)
    sh t4, 6(s6)

# A child fits only when h(child) < bound - depth.
    add t5, s9, t3
    lbu t5, 0(t5)
    add t6, s10, t4
    lbu t6, 0(t6)
    bgeu t5, t6, .Lrubik_child_bound
    mv t5, t6
.Lrubik_child_bound:
    sub t6, s5, s4
    bgeu t5, t6, .Lrubik_search_loop
    add t2, s11, s4
    sb t0, 0(t2)
    addi s4, s4, 1
    addi s6, s6, 16
    sh t3, 0(s6)
    sh t4, 2(s6)
    sb zero, 8(s6)
    sb a3, 9(s6)
    j .Lrubik_search_loop
.Lrubik_backtrack:
    beq s4, a7, .Lrubik_increase_bound
    addi s4, s4, -1
    addi s6, s6, -16
    j .Lrubik_search_loop
.Lrubik_increase_bound:
    addi s5, s5, 1
    li t0, 11
    bgeu t0, s5, .Lrubik_new_bound
    li a0, -1
    j .Lrubik_restore

# Within five remaining moves, finish through the exact sorted table.
.Lrubik_terminal:
    jal ra, .Lrubik_lookup_coords
    li t0, -1
    beq a0, t0, .Lrubik_backtrack
    srli t5, a0, 4
    andi t5, t5, 7
    bltu t6, t5, .Lrubik_backtrack
.Lrubik_tail:
    srli t5, a0, 4
    andi t5, t5, 7
    beq t5, zero, .Lrubik_found
    andi a6, a0, 15
    add t0, s11, s4
    sb a6, 0(t0)
    addi s4, s4, 1
    li a3, 0
    li a4, 0
    li t2, 3
    bltu a6, t2, .Lrubik_tail_face
    li a3, 1
    li a4, 3
    li t2, 6
    bltu a6, t2, .Lrubik_tail_face
    li a3, 2
    li a4, 6
.Lrubik_tail_face:
    sub a6, a6, a4
    addi a6, a6, 1
    slli t2, a3, 2
    add t0, s7, t2
    lw t0, 0(t0)
    add t1, s8, t2
    lw t1, 0(t1)
.Lrubik_tail_turn:
    slli t2, t3, 1
    add t2, t0, t2
    lhu t3, 0(t2)
    slli t2, t4, 1
    add t2, t1, t2
    lhu t4, 0(t2)
    addi a6, a6, -1
    bne a6, zero, .Lrubik_tail_turn
    jal ra, .Lrubik_lookup_coords
    j .Lrubik_tail

# Compute the exact output size before writing any move text.
.Lrubik_found:
    la a3, .Lrubik_suffix
    li t0, 1
    li t1, 0
.Lrubik_measure:
    bgeu t1, s4, .Lrubik_check_capacity
    add t2, s11, t1
    lbu t2, 0(t2)
    add t3, a3, t2
    lbu t3, 0(t3)
    snez t3, t3
    addi t0, t0, 1
    add t0, t0, t3
    beq t1, zero, .Lrubik_measure_next
    addi t0, t0, 1
.Lrubik_measure_next:
    addi t1, t1, 1
    j .Lrubik_measure
.Lrubik_check_capacity:
    bltu s1, t0, .Lrubik_buffer_too_small
    la a4, .Lrubik_face_text
    mv t0, s0
    li t1, 0
.Lrubik_emit:
    bgeu t1, s4, .Lrubik_emit_done
    beq t1, zero, .Lrubik_emit_move
    li t3, 32
    sb t3, 0(t0)
    addi t0, t0, 1
.Lrubik_emit_move:
    add t2, s11, t1
    lbu t2, 0(t2)
    add t3, a4, t2
    lbu t3, 0(t3)
    sb t3, 0(t0)
    addi t0, t0, 1
    add t3, a3, t2
    lbu t3, 0(t3)
    beq t3, zero, .Lrubik_emit_next
    sb t3, 0(t0)
    addi t0, t0, 1
.Lrubik_emit_next:
    addi t1, t1, 1
    j .Lrubik_emit
.Lrubik_emit_done:
    sb zero, 0(t0)
    mv a0, s4
    j .Lrubik_restore
.Lrubik_buffer_too_small:
    sb zero, 0(s0)
    li a0, -2
.Lrubik_restore:
    lw s0, 192(sp)
    lw s1, 196(sp)
    lw s2, 200(sp)
    lw s3, 204(sp)
    lw s4, 208(sp)
    lw s5, 212(sp)
    lw s6, 216(sp)
    lw s7, 220(sp)
    lw s8, 224(sp)
    lw s9, 228(sp)
    lw s10, 232(sp)
    lw s11, 236(sp)
    lw ra, 252(sp)
    addi sp, sp, 256
    ret
# Local helpers preserve t3..t6, a6, a7, and all s registers.
# Form key = permutation * 729 + orientation using only shifts/adds.
.Lrubik_lookup_coords:
    slli a0, t3, 10
    slli t0, t3, 8
    sub a0, a0, t0
    slli t0, t3, 5
    sub a0, a0, t0
    slli t0, t3, 3
    sub a0, a0, t0
    add a0, a0, t3
    add a0, a0, t4
    li t0, 0
    li t1, 12224
    la a1, .Lrubik_near5
.Lrubik_near_loop:
    bgeu t0, t1, .Lrubik_near_missing
    add t2, t0, t1
    srli t2, t2, 1
    slli a2, t2, 2
    add a2, a1, a2
    lw a2, 0(a2)
    srli a3, a2, 7
    beq a0, a3, .Lrubik_near_found
    bltu a3, a0, .Lrubik_near_right
    mv t1, t2
    j .Lrubik_near_loop
.Lrubik_near_right:
    addi t0, t2, 1
    j .Lrubik_near_loop
.Lrubik_near_found:
    mv a0, a2
    ret
.Lrubik_near_missing:
    li a0, -1
    ret

.Lrubik_is11_coords:
    slli a0, t3, 10
    slli t0, t3, 8
    sub a0, a0, t0
    slli t0, t3, 5
    sub a0, a0, t0
    slli t0, t3, 3
    sub a0, a0, t0
    add a0, a0, t3
    add a0, a0, t4
    li t0, 0
    li t1, 2644
    la a1, .Lrubik_far11
.Lrubik_far_loop:
    bgeu t0, t1, .Lrubik_far_missing
    add t2, t0, t1
    srli t2, t2, 1
    slli a2, t2, 2
    add a2, a1, a2
    lw a2, 0(a2)
    beq a0, a2, .Lrubik_far_found
    bltu a2, a0, .Lrubik_far_right
    mv t1, t2
    j .Lrubik_far_loop
.Lrubik_far_right:
    addi t0, t2, 1
    j .Lrubik_far_loop
.Lrubik_far_found:
    li a0, 1
    ret
.Lrubik_far_missing:
    li a0, 0
    ret
    .size rubik_solve_asm, .-rubik_solve_asm

    .section .rodata
    .align 2
.Lrubik_perm_tables:
    .word .Lrubik_perm_r, .Lrubik_perm_b, .Lrubik_perm_d
.Lrubik_orient_tables:
    .word .Lrubik_orient_r, .Lrubik_orient_b, .Lrubik_orient_d
.Lrubik_face_text:
    .ascii "RRRBBBDDD"
.Lrubik_suffix:
    .byte 0, 50, 39, 0, 50, 39, 0, 50, 39
    .include "src/rubik/rubik_tables_asm.inc"
    .include "src/rubik/rubik_terminal_asm.inc"
