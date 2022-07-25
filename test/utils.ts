export const almostEqual = (
	a: number,
	b: number,
	threshold = 0.01
) => {
	return a <= (b + threshold * Math.abs(b)) && a >= (b - threshold * Math.abs(b))
}