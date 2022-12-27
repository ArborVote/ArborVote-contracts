import {ethers} from 'hardhat';

export function customError(errorName: string, ...args: any[]) {
  let argumentString = '';

  if (Array.isArray(args) && args.length) {
    // add quotation marks to first argument if it is of string type
    if (typeof args[0] === 'string') {
      args[0] = `"${args[0]}"`;
    }

    // add joining comma and quotation marks to all subsequent arguments, if they are of string type
    argumentString = args.reduce(function (acc: string, cur: any) {
      if (typeof cur === 'string') return `${acc}, "${cur}"`;
      else return `${acc}, ${cur.toString()}`;
    });
  }

  return `'${errorName}(${argumentString})'`;
}

export const ERRORS = {
  ALREADY_INITIALIZED: 'Initializable: contract is already initialized',
};

export function toBytes(string: string) {
  return ethers.utils.formatBytes32String(string);
}

// convertToStruct takes an array type eg. Inventory.ItemStructOutput and converts it to an object type.
export const convertToStruct = <A extends Array<unknown>>(
  arr: A
): ExtractPropsFromArray<A> => {
  const keys = Object.keys(arr).filter(key => isNaN(Number(key)));
  const result = {};
  // @ts-ignore
  arr.forEach((item, index) => (result[keys[index]] = item));
  return result as A;
};

// This is to remove unnecessary properties from the output type. Use it eg. `ExtractPropsFromArray<Inventory.ItemStructOutput>`
export type ExtractPropsFromArray<T> = Omit<
  T,
  keyof Array<unknown> | `${number}`
>;

export async function getTime(): Promise<number> {
  return (await ethers.provider.getBlock('latest')).timestamp;
}

export async function advanceTime(time: number) {
  await ethers.provider.send('evm_increaseTime', [time]);
  await ethers.provider.send('evm_mine', []);
}

export async function advanceTimeTo(timestamp: number) {
  const delta = timestamp - (await getTime());
  await advanceTime(delta);
}
