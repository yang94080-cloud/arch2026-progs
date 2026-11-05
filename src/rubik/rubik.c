#include "rubik.h"

#include "rubik.h"
#include "rubik_tables.inc"

static const uint16_t *const perm_table[3] = {rubik_perm_r, rubik_perm_b,
                                              rubik_perm_d};

static const uint16_t *const orient_table[3] = {rubik_orient_r, rubik_orient_b,
                                                rubik_orient_d};

static const uint8_t move_face[9] = {0, 0, 0, 1, 1, 1, 2, 2, 2};
static const uint8_t first_move[3] = {0, 3, 6};
static const char face_name[3] = {'R', 'B', 'D'};
static const char suffix[9] = {0, '2', '\'', 0, '2', '\'', 0, '2', '\''};

/* Validate before changing the caller's output buffer. */
static int parse_coordinates(const char *state, uint16_t *p, uint16_t *o)
{
    uint8_t cubies[7];
    unsigned seen = 0;

    for (unsigned i = 0; i < 7; i++) {
        unsigned digit = (unsigned char) state[i];
        if (digit < '1' || digit > '7')
            return 0;

        digit -= '1';
        unsigned bit = 1u << digit;
        if ((seen & bit) != 0u)
            return 0;

        seen |= bit;
        cubies[i] = (uint8_t) digit;
    }

    unsigned orient = 0;
    unsigned sum = 0;

    for (unsigned i = 0; i < 7; i++) {
        unsigned digit = (unsigned char) state[i + 7];
        if (digit < '1' || digit > '3')
            return 0;

        digit -= '1';
        sum += digit;
        if (sum >= 3)
            sum -= 3;

        if (i < 6)
            orient = orient * 3u + digit;
    }

    if (state[14] != '\0' || sum != 0)
        return 0;

    unsigned perm = 0;
    for (unsigned i = 0; i < 7; i++) {
        unsigned smaller = 0;
        for (unsigned j = i + 1; j < 7; j++)
            smaller += (unsigned) (cubies[j] < cubies[i]);

        perm = perm * (7u - i) + smaller;
    }

    *p = (uint16_t) perm;
    *o = (uint16_t) orient;
    return 1;
}

static unsigned lower_bound(uint16_t p, uint16_t o)
{
    unsigned h = rubik_perm_dist[p];
    if (rubik_orient_dist[o] > h)
        h = rubik_orient_dist[o];
    return h;
}

/* One frame per search depth; no recursion or heap allocation. */
struct frame {
    uint16_t p, o, candidate_p, candidate_o;
    uint8_t next;
};

static int search(uint16_t p, uint16_t o, uint8_t path[11])
{
    struct frame stack[12];

    for (unsigned bound = lower_bound(p, o); bound <= 11; bound++) {
        unsigned depth = 0;
        stack[0].p = p;
        stack[0].o = o;
        stack[0].next = 0;

        for (;;) {
            struct frame *f = &stack[depth];

            if (f->p == 0 && f->o == 0)
                return (int) depth;

            if (depth >= bound || f->next >= 9) {
                if (depth == 0)
                    break;

                depth--;
                continue;
            }

            unsigned move = f->next++;
            unsigned face = move_face[move];

            if (depth != 0 && face == move_face[path[depth - 1]]) {
                f->next = (uint8_t) (first_move[face] + 3);
                continue;
            }

            if (move == first_move[face]) {
                f->candidate_p = f->p;
                f->candidate_o = f->o;
            }

            f->candidate_p = perm_table[face][f->candidate_p];
            f->candidate_o = orient_table[face][f->candidate_o];

            if (depth + 1 + lower_bound(f->candidate_p, f->candidate_o) > bound)
                continue;

            path[depth] = (uint8_t) move;
            stack[depth + 1].p = f->candidate_p;
            stack[depth + 1].o = f->candidate_o;

            depth++;
            stack[depth].next = 0;
        }
    }

    return -1;
}

int rubik_solve(const char *state, char *out, size_t cap)
{
    uint16_t p, o;
    if (!parse_coordinates(state, &p, &o))
        return -1;

    if (cap == 0)
        return -2;

    uint8_t path[11];
    int length = search(p, o, path);
    if (length < 0)
        return -1;

    /* Include separators, optional suffixes, and the terminating NUL. */
    size_t needed = 1;
    for (int i = 0; i < length; i++)
        needed += 1u + (unsigned) (suffix[path[i]] != 0) + (unsigned) (i != 0);

    if (cap < needed) {
        out[0] = '\0';
        return -2;
    }

    size_t pos = 0;
    for (int i = 0; i < length; i++) {
        unsigned move = path[i];
        if (i != 0)
            out[pos++] = ' ';

        out[pos++] = face_name[move_face[move]];
        if (suffix[move] != 0)
            out[pos++] = suffix[move];
    }

    out[pos] = '\0';
    return length;
}
