//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library UtilsLib {
    /// @notice Calculate `v * a/b` and round it down. Taken from https://ethereum.stackexchange.com/questions/55701/how-to-do-solidity-percentage-calculation.
    /// @param v The value:
    /// @param a The nominator.
    /// @param b The denominiator.
    /// @return The rounded down result of `v * a/b`.
    function multipyByFraction(uint32 v, uint32 a, uint32 b) public pure returns (uint32) {
        uint32 vdiv = v / b;
        uint32 vmod = v % b;
        uint32 adiv = a / b;
        uint32 amod = a % b;

        return vdiv * adiv * b + vdiv * amod + vmod * adiv + (vmod * amod) / b;
    }

    /// @notice Calculate `v * a/b` and round it down. Taken from https://ethereum.stackexchange.com/questions/55701/how-to-do-solidity-percentage-calculation.
    /// @param v The value:
    /// @param a The nominator.
    /// @param b The denominiator.
    /// @return The rounded down result of `v * a/b`.
    function multipyByFraction(int64 v, int64 a, int64 b) public pure returns (int64) {
        int64 vdiv = v / b;
        int64 vmod = v % b;
        int64 adiv = a / b;
        int64 amod = a % b;

        return vdiv * adiv * b + vdiv * amod + vmod * adiv + (vmod * amod) / b;
    }

    function split(uint32 v, uint32 a, uint32 b) public pure returns (uint32 v1, uint32 v2) {
        v2 = multipyByFraction({v: v, a: b, b: a + b});
        v1 = v - v2;
    }

    /// @notice Finds a value in an array and returns its index in an interval using bisection search. Taken from https://gist.github.com/chriseth/0c671e0dac08c3630f47.
    /// @param array The array to be searched.
    /// @param begin The start of the search internval.
    /// @param end The end of the search internval.
    /// @param value The value to be searched
    /// @return The index of the value in the array interval.
    function findIndexInInterval(
        uint16[] memory array,
        uint16 begin,
        uint16 end,
        uint16 value
    ) public pure returns (uint16) {
        uint16 len = end - begin;
        if (len == 0 || (len == 1 && array[begin] != value)) {
            return type(uint16).max;
        }
        uint16 mid = begin + len / 2;
        uint16 v = array[mid];
        if (value < v)
            return findIndexInInterval({array: array, begin: begin, end: mid, value: value});
        else if (value > v)
            return findIndexInInterval({array: array, begin: mid + 1, end: end, value: value});
        else return mid;
    }

    /// @notice Finds a value in an array and returns its index.
    /// @param array The array to be searched.
    /// @param value The value to be searched
    /// @return The index of the value in the array.
    function findIndex(uint16[] memory array, uint16 value) public pure returns (uint16) {
        return
            findIndexInInterval({array: array, begin: 0, end: uint16(array.length), value: value});
    }

    /// @notice Removes a value in an array by its index.
    /// @param array The array.
    /// @param i The index to be removed
    function removeByIndex(uint16[] storage array, uint16 i) public {
        while (i < array.length - 1) {
            array[i] = array[i + 1];
            i++;
        }
        array.pop();
    }

    /// @notice Removes a value from an array.
    /// @param array The array.
    /// @param value The value to be removed
    function removeByValue(uint16[] storage array, uint16 value) public {
        removeByIndex({array: array, i: findIndex({array: array, value: value})});
    }
}
