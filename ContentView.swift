import Foundation
import SwiftUI

// Expose the Darwin sys_icache_invalidate C function to Swift
@_silgen_name("sys_icache_invalidate")
func sys_icache_invalidate(_ start: UnsafeRawPointer, _ len: Int)

struct ContentView: View {
    @State private var outputText: String = "Tap button to run JIT..."
    
    var body: some View {
        VStack(spacing: 20) {
            Text("ARM64 JIT Emulator")
                .font(.title)
                .bold()
            
            Text(outputText)
                .font(.system(.body, design: .monospaced))
                .padding()
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            
            Button("Run JIT Program") {
                runJITTest()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
    
    func runJITTest() {
        let jit = JITMemory()
        
        // VM Program: Start with input (5), add 10, multiply by 3, return
        let program: [VMInstruction] = [
            .addConstant(10),
            .multiplyConstant(3),
            .returnVal
        ]
        
        if let compiledFunction = jit.compile(program) {
            let initialInput: Int32 = 5
            let result = compiledFunction(initialInput)
            outputText = "Input: \(initialInput)\nExpected: (5 + 10) * 3 = 45\nJIT Result: \(result)"
        } else {
            outputText = "Failed to allocate or compile JIT memory."
        }
    }
}

// 1. VM Instruction Set
enum VMInstruction {
    case addConstant(Int32)
    case multiplyConstant(Int32)
    case returnVal
}

// 2. JIT Engine Wrapper
class JITMemory {
    private var pointer: UnsafeMutableRawPointer?
    private var size: Int
    
    init(maxSize: Int = 4096) {
        self.size = maxSize
        // Allocate page-aligned memory
        self.pointer = mmap(
            nil,
            size,
            PROT_READ | PROT_WRITE,
            MAP_ANON | MAP_PRIVATE,
            -1,
            0
        )
        guard self.pointer != MAP_FAILED else {
            fatalError("Failed to allocate memory via mmap")
        }
    }
    
    func compile(_ instructions: [VMInstruction]) -> (@convention(c) (Int32) -> Int32)? {
        guard let basePtr = pointer else { return nil }
        var stream = basePtr.assumingMemoryBound(to: UInt32.self)
        
        // Encode instructions directly to ARM64 machine code
        for inst in instructions {
            switch inst {
            case .addConstant(let val):
                let encodedAdd = encodeAddImm(imm: val)
                stream.pointee = encodedAdd
                stream = stream.advanced(by: 1)
                
            case .multiplyConstant(let val):
                let loadAndMul = encodeMulImm(imm: val)
                for instructionBytes in loadAndMul {
                    stream.pointee = instructionBytes
                    stream = stream.advanced(by: 1)
                }
                
            case .returnVal:
                // ARM64 RET instruction (0xD65F03C0)
                stream.pointee = 0xD65F03C0
                stream = stream.advanced(by: 1)
            }
        }
        
        // Change memory flags to Executable (W^X compliance)
        let protectResult = mprotect(basePtr, size, PROT_READ | PROT_EXEC)
        guard protectResult == 0 else {
            print("Error: mprotect failed with error code \(errno)")
            return nil
        }
        
        // Invalidate CPU instruction cache
        sys_icache_invalidate(basePtr, size)
        
        // Cast executable pointer to C function signature
        let functionSymbol = unsafeBitCast(basePtr, to: (@convention(c) (Int32) -> Int32).self)
        return functionSymbol
    }
    
    private func encodeAddImm(imm: Int32) -> UInt32 {
        let maskedImm = UInt32(bitPattern: imm) & 0xFFF
        return 0x11000000 | (maskedImm << 10)
    }
    
    private func encodeMulImm(imm: Int32) -> [UInt32] {
        let imm16 = UInt32(bitPattern: imm) & 0xFFFF
        let movzW1 = UInt32(0x52800001) | (imm16 << 5)
        let mulOp: UInt32 = 0x1B017C00
        return [movzW1, mulOp]
    }
    
    deinit {
        if let ptr = pointer {
            munmap(ptr, size)
        }
    }
}
