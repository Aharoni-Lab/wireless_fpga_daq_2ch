import editdistance
import numpy as np
import pandas as pd
from bitstring import Array, BitArray, Bits


def shift_to_preamble(a, pre, last=False, **kwargs):
    if last:
        pos = list(a.findall(pre, **kwargs))
    else:
        pos = a.find(pre, **kwargs)
    if pos:
        if last:
            return a[pos[-1] :]
        else:
            return a[pos[0] :]
    else:
        print("Cannot find preamble")
        return a


def check_repeat_pattern(a, pat, rpt, pre=None, post=None, **kwargs):
    pat = pat * rpt
    if pre is not None:
        pat = pre + pat
    if post is not None:
        pat = pat + post
    pat = (pat * (int(len(a) / len(pat)) + 1))[: len(a)]
    return resolve_error(a, pat, **kwargs)


def check_repeat_pattern_levenshtein(a, pat, rpt, pre=None, post=None):
    pat = pat * rpt
    if pre is not None:
        pat = pre + pat
    if post is not None:
        pat = pat + post
    pat = (pat * (int(len(a) / len(pat)) + 1))[: len(a)]
    return editdistance.eval(a, pat)


def sh_bitarray(arr, sh):
    if sh > 0:
        return arr >> sh
    elif sh < 0:
        return arr << abs(sh)
    else:
        return arr


def sh_match(sig, ref, sh):
    sig_sh = sh_bitarray(sig, sh)
    if sh > 0:
        return (sig_sh[sh:] ^ ref[sh:]).count(1) + abs(sh)
    elif sh < 0:
        return (sig_sh[:sh] ^ ref[:sh]).count(1) + abs(sh)
    else:
        return (sig_sh ^ ref).count(1)


def resolve_error(
    sig, ref, shifts=[-3, -2, -1, 0, 1, 2, 3], look_ahead=163840, early_stop=None
):
    sig = sig.copy()
    err = sig ^ ref
    idx = 0
    err_df = []
    arr_len = len(sig)
    while idx < len(sig):
        if early_stop is not None and len(err_df) >= early_stop:
            arr_len = idx
            break
        next_err = err.find(Bits(bool=True), start=idx)
        if not next_err:
            break
        else:
            next_err = next_err[0]
        sig_match = sig[next_err : next_err + look_ahead]
        ref_match = ref[next_err : next_err + look_ahead]
        shift_err = pd.Series({sh: sh_match(sig_match, ref_match, sh) for sh in shifts})
        sh = shift_err.idxmin()
        sig[next_err:] = sh_bitarray(sig[next_err:], sh)
        err_df.append(pd.Series({"index": next_err, "bitshift": sh}))
        err = sig ^ ref
        idx = next_err + 1
    if err_df:
        err_df = pd.concat(err_df, axis="columns", ignore_index=True).T
        nerr = len(err_df)
    else:
        err_df = None
        nerr = 0
    err_rate = nerr / arr_len
    return sig, err, err_df, err_rate, arr_len


def generate_incremental_pattern(preamble=None, npre_head=5, gap=None, buf_len=163840):
    if preamble is not None:
        header = preamble * npre_head
        if gap is not None:
            header = gap + header
    else:
        header = Bits()
    data_len = buf_len - len(header)
    assert (data_len % 32) == 0
    nrpt = int(data_len / 32)
    pat = np.tile([3, 2, 1, 0], (nrpt, 1)) + np.arange(nrpt).reshape((-1, 1))
    pat = Array("uint:8", (pat % 256).reshape(-1))
    return header + pat.data
