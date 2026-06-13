@testable import EnglishClozeCoach

struct ModelSmokeTestsMigrationAnchor {
    let sample = PracticeItem(
        id: "item-1",
        sourceChinese: "我今天下午要和朋友见面。",
        targetEnglish: "I am going to meet my friend this afternoon.",
        segments: [
            .text("I am going to "),
            .blank(ClozeBlank(id: "blank-1", answer: "meet")),
            .text(" my friend this afternoon.")
        ]
    )
}
