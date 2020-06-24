#if !canImport(ObjectiveC)
import XCTest

extension CommandExtensionTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__CommandExtensionTests = [
        ("testAsync", testAsync),
        ("testAsyncStream", testAsyncStream),
        ("testAsyncStreamJoin", testAsyncStreamJoin),
        ("testInvalidJSON", testInvalidJSON),
        ("testInvalidJSONDecodable", testInvalidJSONDecodable),
        ("testJSONDecodable", testJSONDecodable),
        ("testRunBoolFalse", testRunBoolFalse),
        ("testRunBoolTrue", testRunBoolTrue),
        ("testRunData", testRunData),
        ("testRunDataJoin", testRunDataJoin),
        ("testRunFile", testRunFile),
        ("testRunJSON", testRunJSON),
        ("testRunLines", testRunLines),
        ("testRunString", testRunString),
        ("testRunStringBadEncoding", testRunStringBadEncoding),
        ("testRunStringBlank", testRunStringBlank),
        ("testRunStringJoin", testRunStringJoin),
        ("testRunSucceeds", testRunSucceeds),
    ]
}

extension CommandResultExtensionTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__CommandResultExtensionTests = [
        ("testDefaultSucceed", testDefaultSucceed),
        ("testDefaultSucceedFail", testDefaultSucceedFail),
        ("testFinish", testFinish),
    ]
}

extension FDWrapperCommandExtensionsTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__FDWrapperCommandExtensionsTests = [
        ("testInputEncodable", testInputEncodable),
        ("testInputFromFile", testInputFromFile),
        ("testInputJSON", testInputJSON),
        ("testInputStringFailure", testInputStringFailure),
        ("testInputStringSuccess", testInputStringSuccess),
        ("testOutputAppendingCreate", testOutputAppendingCreate),
        ("testOutputAppendingNoCreateFail", testOutputAppendingNoCreateFail),
        ("testOutputAppendingNoCreateSuccess", testOutputAppendingNoCreateSuccess),
        ("testOutputCreatingFileFailure", testOutputCreatingFileFailure),
        ("testOutputCreatingFileSuccess", testOutputCreatingFileSuccess),
        ("testOutputOverwritingFile", testOutputOverwritingFile),
    ]
}

extension FDWrapperCommandTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__FDWrapperCommandTests = [
        ("testConstructor", testConstructor),
        ("testInvalidCoreAsync", testInvalidCoreAsync),
        ("testResultFailed", testResultFailed),
        ("testResultSucceeds", testResultSucceeds),
        ("testValidCoreAsync", testValidCoreAsync),
    ]
}

extension IntegrationTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__IntegrationTests = [
        ("testAbsPath", testAbsPath),
        ("testCmdArgList", testCmdArgList),
        ("testFailureIsntRunning", testFailureIsntRunning),
        ("testFalseRun", testFalseRun),
        ("testIsRunning", testIsRunning),
        ("testKillDeadProcess", testKillDeadProcess),
        ("testKillRunningProcess", testKillRunningProcess),
        ("testKillStop", testKillStop),
        ("testNonExistantProgram", testNonExistantProgram),
        ("testNonExistantProgramInPipeline", testNonExistantProgramInPipeline),
        ("testOverwriteEnv", testOverwriteEnv),
        ("testPipeFailFails", testPipeFailFails),
        ("testPipes", testPipes),
        ("testReadmeExamples", testReadmeExamples),
        ("testRunBoolFalse", testRunBoolFalse),
        ("testRunBoolTrue", testRunBoolTrue),
        ("testRunStringSucceeds", testRunStringSucceeds),
    ]
}

extension PipelineTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__PipelineTests = [
        ("testPipeFail0", testPipeFail0),
        ("testPipeFail1", testPipeFail1),
        ("testPipeFail2", testPipeFail2),
        ("testPipeIsRunning", testPipeIsRunning),
        ("testPipeKillFailure", testPipeKillFailure),
        ("testPipeKillSuccess", testPipeKillSuccess),
        ("testPipeSucceed", testPipeSucceed),
        ("testPipeSucceedFails", testPipeSucceedFails),
        ("testPipeSyntax", testPipeSyntax),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(CommandExtensionTests.__allTests__CommandExtensionTests),
        testCase(CommandResultExtensionTests.__allTests__CommandResultExtensionTests),
        testCase(FDWrapperCommandExtensionsTests.__allTests__FDWrapperCommandExtensionsTests),
        testCase(FDWrapperCommandTests.__allTests__FDWrapperCommandTests),
        testCase(IntegrationTests.__allTests__IntegrationTests),
        testCase(PipelineTests.__allTests__PipelineTests),
    ]
}
#endif