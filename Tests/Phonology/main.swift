import Foundation

func verify(_ actual: String, equals expected: String, in phrase: String) {
    guard actual == expected else {
        fputs("FAIL: \(phrase): expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

verify(HungarianPhonology.approximateIPA("Hogy vagy?"), equals: "hoɟ vɒɟ", in: "Hogy vagy?")
verify(HungarianPhonology.approximateIPA("Hogi vagi"), equals: "hoɡi vɒɡi", in: "Hogi vagi")
verify(HungarianPhonology.approximateIPA("GY TY NY LY"), equals: "ɟ c ɲ j", in: "palatal digraphs")
verify(HungarianPhonology.approximateIPA("sz s zs cs dzs"), equals: "s ʃ ʒ t͡ʃ d͡ʒ", in: "sibilants")
verify(HungarianPhonology.approximateIPA("dz c"), equals: "d͡z t͡s", in: "affricates")
verify(HungarianPhonology.approximateIPA("meggy"), equals: "mɛɟː", in: "long gy")
verify(HungarianPhonology.approximateIPA("hosszú"), equals: "hosːuː", in: "long sz")
verify(HungarianPhonology.approximateIPA("ddzs"), equals: "d͡ʒː", in: "long dzs")
verify(HungarianPhonology.approximateIPA("gyönyörű"), equals: "ɟøɲøryː", in: "accented vowels")
guard HungarianPhonology.transcribe("Gy").first?.isPalatalStop == true,
      HungarianPhonology.transcribe("SZ").first?.isSibilant == true,
      HungarianPhonology.transcribe("gy").count == 1,
      HungarianPhonology.transcribe("dzs").count == 1 else {
    fputs("FAIL: multi-character Hungarian phoneme classification\n", stderr)
    exit(1)
}
print("PASS: Hungarian digraphs, trigraph, long consonants and IPA distinctions")
