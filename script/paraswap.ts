import {getParaswapCalldata} from '../test/helpers/paraswap'

const [
  fromToken,
  toToken,
  amount,
  userAddr,
  maxImpact
] = process.argv.slice(2)

getParaswapCalldata(
    fromToken, toToken, amount, userAddr, Number(maxImpact)
).then(res => console.log(res.data))