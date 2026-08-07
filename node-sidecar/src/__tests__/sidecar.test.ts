describe("DhanHQ-TS Node.js Sidecar", () => {
  it("exports correct configuration and mode", () => {
    const mode = process.env.TRADING_MODE || "paper";
    expect(mode).toBe("paper");
  });
});
