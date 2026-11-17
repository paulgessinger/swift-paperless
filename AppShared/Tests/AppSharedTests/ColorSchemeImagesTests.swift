import Testing

@testable import AppShared

@Suite
struct ColorSchemeImagesTests {
  private let pair = """
    Intro.

    ![](a.png#only-light)
    ![](a-dark.png#only-dark)

    Outro.
    """

  @Test func keepsTheLightImageInLightMode() {
    #expect(
      pair.keepingImages(dark: false) == """
        Intro.

        ![](a.png#only-light)

        Outro.
        """)
  }

  @Test func keepsTheDarkImageInDarkMode() {
    #expect(
      pair.keepingImages(dark: true) == """
        Intro.

        ![](a-dark.png#only-dark)

        Outro.
        """)
  }

  @Test func dropsAttributeListsWithTheImage() {
    let text =
      "![Alt](a-dark.png#only-dark){width=\"400\"}\n![Alt](a.png#only-light){width=\"400\"}"
    #expect(text.keepingImages(dark: false) == "![Alt](a.png#only-light){width=\"400\"}")
  }

  @Test func leavesUnmarkedImagesAlone() {
    let text = "![](a.png)\n![](b.png#section)"
    #expect(text.keepingImages(dark: true) == text)
    #expect(text.keepingImages(dark: false) == text)
  }
}
